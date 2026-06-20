import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String _profileCompleteKey(String uid) => 'profile_complete_$uid';

  Future<bool> isProfileComplete() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final prefs = await SharedPreferences.getInstance();

    final cached = prefs.getBool(_profileCompleteKey(uid));
    if (cached == true) return true;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));

      if (!doc.exists) {
        await prefs.setBool(_profileCompleteKey(uid), false);
        return false;
      }

      final data = doc.data();
      // Profile is only complete when ALL required fields are filled —
      // not just fullName from Google account. Also require age and
      // gamblingType which are collected in CompleteProfileScreen.
      final isComplete = data != null &&
          (data['fullName'] ?? '').toString().trim().isNotEmpty &&
          data['age'] != null &&
          (data['gamblingType'] ?? '').toString().trim().isNotEmpty;

      await prefs.setBool(_profileCompleteKey(uid), isComplete);
      return isComplete;
    } catch (_) {
      return prefs.getBool(_profileCompleteKey(uid)) ?? false;
    }
  }

  Future<void> markProfileComplete() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_profileCompleteKey(uid), true);
  }

  Future<void> clearProfileCache() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileCompleteKey(uid));
  }

  /// Called after email/PIN sign up — always writes a fresh document
  /// and marks profile as needing completion.
 Future<void> createUserProfile({
  required String fullName,
  required String email,
}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return;
  // Don't write to Firestore yet — CompleteProfileScreen handles the full write
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_profileCompleteKey(uid), false);
}

  /// Called after Google sign-in — only writes createdAt if document
  /// doesn't exist yet (new user). Never marks profile complete so
  /// CompleteProfileScreen still runs for new Google users.
  /// Returning Google users with complete profiles are unaffected.
  Future<void> createUserProfileIfNew({
    required String fullName,
    required String email,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) return; // returning user — don't overwrite

    // New Google user — write minimal document with createdAt.
    // Do NOT mark profile complete — ProfileCheckWrapper will route
    // them to CompleteProfileScreen since age and gamblingType are missing.
    await _firestore.collection('users').doc(uid).set({
      'fullName': fullName,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Explicitly clear cache so isProfileComplete() hits Firestore
    // and correctly returns false (age/gamblingType not filled yet)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileCompleteKey(uid));
  }
}