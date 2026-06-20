import 'package:betcontrol_main/services/connectivity_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(firebaseAuthProvider));
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final FirebaseAuth _auth;

  AuthController(this._auth) : super(const AsyncValue.data(null));

  // Email & Password Sign Up
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(fullName);
      await credential.user?.sendEmailVerification();
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e.message ?? 'Sign up failed', StackTrace.current);
    }
  }

  // Email & Password Sign In
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e.message ?? 'Sign in failed', StackTrace.current);
    }
  }

  // Google Sign In
  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      await _auth.signOut();
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        state = const AsyncValue.data(null);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e.message ?? 'Google sign in failed', StackTrace.current);
    }
  }

  // Forgot Password
  Future<void> resetPassword(String email) async {
    state = const AsyncValue.loading();
    try {
      await _auth.sendPasswordResetEmail(email: email);
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e.message ?? 'Reset failed', StackTrace.current);
    }
  }

  // Sign Out
  Future<void> signOut() async {
    final hasInternet = await ConnectivityService().hasInternetConnection();
    if (!hasInternet) {
      state = AsyncValue.error(
        'No internet connection. Please try again.',
        StackTrace.current,
      );
      return;
    }
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
