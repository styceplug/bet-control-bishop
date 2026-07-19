const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();
const auth = getAuth();

// ── Helper: send FCM to a single user ─────────────────────────────────────
async function sendFcmNotification(fcmToken, title, body) {
  if (!fcmToken) return;
  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      android: {
        notification: {
          channelId: "betcontrol_alerts",
          color: "#00D4AA",
          icon: "ic_launcher",
          priority: "high",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            badge: 1,
          },
        },
      },
    });
  } catch (error) {
    console.warn(`FCM send failed: ${error.message}`);
  }
}

// ── Verify Payment — called by app instead of hitting Paystack directly ────
exports.verifyPayment = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method not allowed");
  }

  try {
    const authHeader = req.headers.authorization || "";
    if (!authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Unauthorized" });
    }

    const idToken = authHeader.split("Bearer ")[1];
    let decodedToken;
    try {
      decodedToken = await auth.verifyIdToken(idToken);
    } catch (e) {
      return res.status(401).json({ error: "Invalid token" });
    }

    const { reference } = req.body;
    if (!reference) {
      return res.status(400).json({ error: "Missing reference" });
    }

    const secret = process.env.PAYSTACK_SECRET_KEY;
    if (!secret) {
      console.error("PAYSTACK_SECRET_KEY not set");
      return res.status(500).json({ error: "Server configuration error" });
    }

    const axios = require("axios");
    const response = await axios.get(
      `https://api.paystack.co/transaction/verify/${reference}`,
      {
        headers: {
          Authorization: `Bearer ${secret}`,
          "Content-Type": "application/json",
        },
        timeout: 30000,
      }
    );

    if (response.data.status !== true || !response.data.data) {
      return res.status(200).json({ status: "failed" });
    }

    const txData = response.data.data;
    const metadata = txData.metadata || {};

    if (metadata.userId && metadata.userId !== decodedToken.uid) {
      console.warn(`User ${decodedToken.uid} tried to verify reference for ${metadata.userId}`);
      return res.status(403).json({ error: "Forbidden" });
    }

    return res.status(200).json({ status: txData.status });
  } catch (error) {
    console.error("verifyPayment error:", error.message);
    return res.status(200).json({ status: null });
  }
});

// ── RevenueCat Webhook — source of truth for Apple subscriptions ───────────
exports.revenueCatWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method not allowed");
  }

  try {
    const expectedAuth = process.env.REVENUECAT_WEBHOOK_AUTH;
    if (!expectedAuth) {
      console.error("REVENUECAT_WEBHOOK_AUTH not set");
      return res.status(500).send("Server configuration error");
    }

    const authHeader = req.headers.authorization || "";
    if (authHeader !== expectedAuth && authHeader !== `Bearer ${expectedAuth}`) {
      console.warn("RevenueCat webhook rejected: bad authorization header");
      return res.status(401).send("Unauthorized");
    }

    const event = req.body && req.body.event;
    if (!event || !event.type) {
      return res.status(400).send("Missing RevenueCat event");
    }

    const userId = event.app_user_id;
    if (!userId || userId.startsWith("$RCAnonymousID")) {
      console.warn(`RevenueCat event skipped for anonymous user: ${userId || "missing"}`);
      return res.status(200).send("OK");
    }

    const entitlementIds = Array.isArray(event.entitlement_ids)
      ? event.entitlement_ids
      : [];
    if (entitlementIds.length && !entitlementIds.includes("BetControl")) {
      console.log(`RevenueCat event skipped for other entitlement: ${entitlementIds.join(",")}`);
      return res.status(200).send("OK");
    }

    const expirationMs = Number(event.expiration_at_ms || 0);
    const expirationDate = expirationMs > 0 ? new Date(expirationMs) : null;
    const eventType = event.type;
    const activeEventTypes = new Set([
      "INITIAL_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "PRODUCT_CHANGE",
      "SUBSCRIPTION_EXTENDED",
      "TEMPORARY_ENTITLEMENT_GRANT",
    ]);

    const userUpdate = {
      subscriptionProvider: "apple",
      appleRevenueCatAppUserId: userId,
      appleEntitlementIds: entitlementIds,
      lastRevenueCatEventType: eventType,
      lastRevenueCatEventAt: FieldValue.serverTimestamp(),
    };

    if (event.product_id) userUpdate.appleProductId = event.product_id;
    if (event.store) userUpdate.appleStore = event.store;
    if (event.environment) userUpdate.appleEnvironment = event.environment;
    if (event.period_type) userUpdate.applePeriodType = event.period_type;
    if (event.transaction_id) userUpdate.appleTransactionId = event.transaction_id;
    if (event.original_transaction_id) {
      userUpdate.appleOriginalTransactionId = event.original_transaction_id;
    }
    if (expirationDate) {
      userUpdate.subscriptionExpiry = Timestamp.fromDate(expirationDate);
    }

    if (eventType === "EXPIRATION") {
      userUpdate.subscriptionActive = false;
    } else if (activeEventTypes.has(eventType)) {
      userUpdate.subscriptionActive = expirationDate
        ? expirationDate.getTime() > Date.now()
        : true;
    }

    await db.collection("users").doc(userId).set(userUpdate, { merge: true });

    if (activeEventTypes.has(eventType)) {
      const transactionId =
        event.transaction_id ||
        event.original_transaction_id ||
        `${eventType}_${Date.now()}`;
      await db.collection("users").doc(userId)
        .collection("payments")
        .doc(`apple_${transactionId}`)
        .set({
          reference: transactionId,
          provider: "apple",
          source: "revenuecat_webhook",
          productId: event.product_id || null,
          entitlementIds,
          amount: event.price || null,
          currency: event.currency || null,
          paidAt: event.purchased_at_ms
            ? Timestamp.fromDate(new Date(Number(event.purchased_at_ms)))
            : FieldValue.serverTimestamp(),
          expiresAt: expirationDate ? Timestamp.fromDate(expirationDate) : null,
          eventType,
          environment: event.environment || null,
        }, { merge: true });
    }

    console.log(`RevenueCat ${eventType} processed for ${userId}`);
    return res.status(200).send("OK");
  } catch (error) {
    console.error("RevenueCat webhook error:", error);
    return res.status(200).send("OK");
  }
});

// ── Runs every day at 11pm UTC (midnight WAT) ─────────────────────────────
exports.enforceSubscriptionExpiry = onSchedule(
  { schedule: "0 23 * * *", timeZone: "UTC" },
  async () => {
    try {
      const now = new Date();

      const reminderWindowStart = new Date(now.getTime() + 23 * 60 * 60 * 1000);
      const reminderWindowEnd = new Date(now.getTime() + 25 * 60 * 60 * 1000);

      const snapshot = await db.collection("users")
        .where("subscriptionActive", "==", true)
        .get();

      if (snapshot.empty) {
        console.log("No active subscriptions to check.");
        return;
      }

      const expiredBatch = db.batch();
      let expiredCount = 0;
      let reminderCount = 0;
      let notifiedCount = 0;
      const tasks = [];

      snapshot.forEach((doc) => {
        const data = doc.data();
        if (data.adminOverride === true) return;

        const expiry = data.subscriptionExpiry;
        if (!expiry) {
          expiredBatch.update(doc.ref, { subscriptionActive: false });
          expiredCount++;
          return;
        }

        const expiryDate = expiry.toDate();
        const fcmToken = data.fcmToken || null;

        // ── Expired ────────────────────────────────────────────────────────
        if (now > expiryDate) {
          expiredBatch.update(doc.ref, { subscriptionActive: false });
          expiredCount++;
          tasks.push(
            sendFcmNotification(
              fcmToken,
              "BetControl",
              "Your subscription has expired. Renew now to keep gambling sites blocked."
            )
          );
          notifiedCount++;
          return;
        }

        // ── Expiring within ~24hrs ──────────────────────────────────────────
        if (expiryDate >= reminderWindowStart && expiryDate <= reminderWindowEnd) {
          const lastReminder = data.lastExpiryReminderSent
            ? data.lastExpiryReminderSent.toDate()
            : null;
          const alreadySentToday =
            lastReminder &&
            lastReminder.toDateString() === now.toDateString();

          if (!alreadySentToday) {
            tasks.push(
              sendFcmNotification(
                fcmToken,
                "BetControl",
                "Today is your last day. Renew your subscription to keep your protection active."
              ).then(() =>
                doc.ref.update({
                  lastExpiryReminderSent: FieldValue.serverTimestamp(),
                })
              )
            );
            reminderCount++;
          }
        }
      });

      const commitTasks = [];
      if (expiredCount > 0) commitTasks.push(expiredBatch.commit());
      commitTasks.push(...tasks);
      await Promise.all(commitTasks);

      console.log(`Expired: ${expiredCount}, Reminders: ${reminderCount}, Expiry notifications: ${notifiedCount}`);
    } catch (error) {
      console.error("Subscription enforcement error:", error);
    }
  }
);

// ── Paystack Webhook ───────────────────────────────────────────────────────
exports.paystackWebhook = onRequest(async (req, res) => {
  try {
    const crypto = require("crypto");
    const secret = process.env.PAYSTACK_SECRET_KEY;

    if (!secret) {
      console.error("PAYSTACK_SECRET_KEY not set");
      return res.status(500).send("Server error");
    }

    const hash = crypto
      .createHmac("sha512", secret)
      .update(JSON.stringify(req.body))
      .digest("hex");

    if (hash !== req.headers["x-paystack-signature"]) {
      console.warn("Invalid Paystack signature");
      return res.status(401).send("Unauthorized");
    }

    const event = req.body;
    if (event.event !== "charge.success") {
      return res.status(200).send("OK");
    }

    const data = event.data;
    const reference = data.reference;
    const metadata = data.metadata || {};
    const userId = metadata.userId;
    const type = metadata.type;

    if (!userId || type !== "subscription") {
      console.error("Missing userId or wrong type in metadata");
      return res.status(200).send("OK");
    }

    // ── Amount check — reject underpayments ───────────────────────────────
    const amountPaid = data.amount; // Paystack sends amount in kobo
    const expectedAmount = 150000;  // ₦1,500 in kobo
    if (amountPaid < expectedAmount) {
      console.warn(`Underpayment rejected: ${amountPaid} kobo from user ${userId}. Expected ${expectedAmount} kobo.`);
      return res.status(200).send("OK");
    }

    // ── Duplicate webhook check ───────────────────────────────────────────
    const existing = await db.collection("users")
      .doc(userId)
      .collection("payments")
      .where("reference", "==", reference)
      .limit(1)
      .get();

    if (!existing.empty) {
      console.log(`Duplicate webhook — skipping: ${reference}`);
      return res.status(200).send("OK");
    }

    const expiry = new Date();
    expiry.setDate(expiry.getDate() + 30);

    const userDoc = await db.collection("users").doc(userId).get();
    const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;

    await db.collection("users").doc(userId).update({
      subscriptionActive: true,
      subscriptionExpiry: Timestamp.fromDate(expiry),
      lastPaymentReference: reference,
      lastPaymentDate: FieldValue.serverTimestamp(),
    });

    await db.collection("users").doc(userId)
      .collection("payments").add({
        reference: reference,
        amount: 1500,
        currency: "NGN",
        paidAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromDate(expiry),
        source: "webhook",
      });

    await sendFcmNotification(
      fcmToken,
      "BetControl",
      "Payment confirmed! Your protection is now active for 30 days."
    );

    console.log(`Subscription activated via webhook: ${userId}`);
    return res.status(200).send("OK");
  } catch (error) {
    console.error("Webhook error:", error);
    return res.status(200).send("OK");
  }
});
