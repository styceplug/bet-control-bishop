import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class ProfileImageService {
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  Future<String?> pickAndUploadImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return null;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      final file = File(picked.path);
      final ref = _storage.ref().child('profile_images/$uid.jpg');

      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await _firestore.collection('users').doc(uid).update({
        'profileImageUrl': url,
      });

      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeImage() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await _storage.ref().child('profile_images/$uid.jpg').delete();
      await _firestore.collection('users').doc(uid).update({
        'profileImageUrl': FieldValue.delete(),
      });
    } catch (_) {}
  }
}