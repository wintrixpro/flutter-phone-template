import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final _fnameController = TextEditingController();
  final _lnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passController = TextEditingController();
  final _cpassController = TextEditingController();
  final _referralController = TextEditingController();

  bool _cbTerms = false;
  bool _isLoading = false;
  String _btnText = "SIGN UP";
  
  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? _verificationId;

  @override
  void dispose() {
    _fnameController.dispose();
    _lnameController.dispose();
    _phoneController.dispose();
    _passController.dispose();
    _cpassController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  // ────────── Validation & Flow ──────────
  void _validateAndStartRegistration() async {
    final fname = _fnameController.text.trim();
    final lname = _lnameController.text.trim();
    final rawNumber = _phoneController.text.trim();
    final password = _passController.text;
    final confirmPass = _cpassController.text;

    if (fname.isEmpty) return _showSnackBar("First Name is required");
    if (lname.isEmpty) return _showSnackBar("Last Name is required");
    if (rawNumber.length != 10) return _showSnackBar("Enter 10-digit number");
    if (password.length < 6) return _showSnackBar("Password min 6 characters");
    if (password != confirmPass) return _showSnackBar("Passwords do not match");
    if (!_cbTerms) return _showSnackBar("Please accept the Terms & Conditions");

    final phoneNumber = "+91$rawNumber";
    _checkPhoneAndSendOTP(phoneNumber, password, "$fname $lname");
  }

  // 1. Check if number already exists
  void _checkPhoneAndSendOTP(String phone, String password, String fullName) async {
    _setLoading(true, "Checking phone number...");

    try {
      final snapshot = await _dbRef.child("profiles").orderByChild("phone").equalTo(phone).get();
      
      if (snapshot.exists) {
        _setLoading(false, "SIGN UP");
        _showSnackBar("This number is already registered. Please login.");
      } else {
        _sendPhoneOTP(phone, password, fullName);
      }
    } catch (e) {
      _setLoading(false, "SIGN UP");
      _showSnackBar("Database error: ${e.toString()}");
    }
  }

  // 2. Send Firebase OTP
  void _sendPhoneOTP(String phone, String password, String fullName) async {
    _setLoading(true, "Sending OTP...");

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        _setLoading(false, "SIGN UP");
        _registerWithPhoneCredential(credential, password, fullName, phone);
      },
      verificationFailed: (FirebaseAuthException e) {
        _setLoading(false, "SIGN UP");
        _showSnackBar("OTP Failed: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _setLoading(false, "VERIFY OTP & SIGN UP");
        _showOTPDialog(phone, password, fullName);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // 3. Custom OTP Dialog with 6 Fields & Timer
  void _showOTPDialog(String phone, String password, String fullName) {
    List<TextEditingController> otpControllers = List.generate(6, (_) => TextEditingController());
    List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());
    int secondsLeft = 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (secondsLeft > 0) {
                setDialogState(() => secondsLeft--);
              } else {
                timer?.cancel();
              }
            });

            return AlertDialog(
              title: Text("OTP sent to $phone", style: const TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 35,
                        child: TextField(
                          controller: otpControllers[index],
                          focusNode: focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: Alignment.center,
                          maxLength: 1,
                          decoration: const InputDecoration(counterText: ""),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 5) {
                              focusNodes[index + 1].requestFocus();
                            } else if (value.isEmpty && index > 0) {
                              focusNodes[index - 1].requestFocus();
                            }
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  secondsLeft > 0
                      ? Text("Resend in ${secondsLeft}s")
                      : TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            timer?.cancel();
                            _sendPhoneOTP(phone, password, fullName);
                          },
                          child: const Text("Resend OTP"),
                        ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    String otp = otpControllers.map((c) => c.text).join();
                    if (otp.length == 6) {
                      Navigator.pop(context);
                      timer?.cancel();
                      PhoneAuthCredential credential = PhoneAuthProvider.credential(
                        verificationId: _verificationId!,
                        smsCode: otp,
                      );
                      _registerWithPhoneCredential(credential, password, fullName, phone);
                    } else {
                      _showSnackBar("Please enter complete 6-digit OTP.");
                    }
                  },
                  child: const Text("Verify"),
                )
              ],
            );
          },
        );
      },
    ).then((_) => timer?.cancel());
  }

  // 4. Create Account and Link
  void _registerWithPhoneCredential(PhoneAuthCredential phoneCred, String password, String fullName, String phone) async {
    _setLoading(true, "Creating account...");
    try {
      // क्लीन ईमेल जो बैकएंड के लिए काम आए (डेटाबेस के लिए नहीं)
      final dummyEmail = "${phone.replaceAll("+", "")}@wintrix.app";
      
      // Create user with email and password
      UserCredential userCred = await _auth.createUserWithEmailAndPassword(
        email: dummyEmail,
        password: password,
      );

      // Link phone credential
      if (userCred.user != null) {
        await userCred.user!.linkWithCredential(phoneCred);
        _saveUserProfile(userCred.user!.uid, fullName, phone, "");
      }
    } catch (e) {
      _setLoading(false, "SIGN UP");
      _showSnackBar("Registration failed: ${e.toString()}");
    }
  }

  // 5. Clean Database Save (UID is Main Key)
  void _saveUserProfile(String uid, String name, String phone, String email) async {
    final profile = {
      "id": uid,
      "name": name,
      "phone": phone,
      "email": email, // अब यहाँ फ़ोन नंबर नहीं, साफ़ ईमेल (या खाली स्ट्रिंग) जाएगा!
      "referred_by": _referralController.text.trim(),
      "is_banned": false,
      "profile_pic": "",
      "created_at": ServerValue.timestamp,
      "updated_at": ServerValue.timestamp,
    };

    try {
      await _dbRef.child("profiles").child(uid).set(profile);
      await _saveLoginPrefs(uid, name, phone);
      _navigateToHome();
    } catch (e) {
      _setLoading(false, "SIGN UP");
      _showSnackBar("Failed to save profile.");
    }
  }

  // ────────── Google Sign‑In ──────────
  void _signUpWithGoogle() async {
    _setLoading(true, "Signing up with Google...");
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false, "SIGN UP");
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCred = await _auth.signInWithCredential(credential);
      User? user = userCred.user;

      if (user != null) {
        final snapshot = await _dbRef.child("profiles").child(user.uid).get();

        if (snapshot.exists) {
          final isBanned = snapshot.child("is_banned").value == true;
          if (isBanned) {
            await _auth.signOut();
            _setLoading(false, "SIGN UP");
            _showBanDialog();
            return;
          }
          String existingName = snapshot.child("name").value as String? ?? user.displayName ?? "Player";
          await _saveLoginPrefs(user.uid, existingName, "");
          _navigateToHome();
        } else {
          // New Google Profile
          final newProfile = {
            "id": user.uid,
            "name": user.displayName ?? "Player",
            "email": user.email ?? "",
            "phone": "",
            "profile_pic": user.photoURL ?? "",
            "is_banned": false,
            "created_at": ServerValue.timestamp,
          };
          await _dbRef.child("profiles").child(user.uid).set(newProfile);
          await _saveLoginPrefs(user.uid, user.displayName ?? "Player", "");
          _navigateToHome();
        }
      }
    } catch (e) {
      _setLoading(false, "SIGN UP");
      _showSnackBar("Google Auth Failed.");
    }
  }

  // ────────── Helpers ──────────
  void _setLoading(bool loading, String text) {
    setState(() {
      _isLoading = loading;
      _btnText = text;
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveLoginPrefs(String uid, String name, String phoneStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("userId", uid);
    await prefs.setString("userName", name);
    await prefs.setString("phone", phoneStr);
    await prefs.setBool("isLoggedIn", true);
  }

  void _navigateToHome() {
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  void _showBanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("ACCOUNT SUSPENDED"),
        content: const Text("Your account has been permanently banned."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("EXIT"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(controller: _fnameController, decoration: const InputDecoration(labelText: "First Name")),
                TextField(controller: _lnameController, decoration: const InputDecoration(labelText: "Last Name")),
                TextField(controller: _phoneController, decoration: const InputDecoration(labelText: "Phone (10 digits)"), keyboardType: TextInputType.phone),
                TextField(controller: _passController, decoration: const InputDecoration(labelText: "Password"), obscureText: true),
                TextField(controller: _cpassController, decoration: const InputDecoration(labelText: "Confirm Password"), obscureText: true),
                TextField(controller: _referralController, decoration: const InputDecoration(labelText: "Referral Code (Optional)")),
                Row(
                  children: [
                    Checkbox(value: _cbTerms, onChanged: (val) => setState(() => _cbTerms = val ?? false)),
                    const Expanded(child: Text("I accept the Terms & Conditions")),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _validateAndStartRegistration,
                  child: Text(_btnText),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _signUpWithGoogle,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  child: const Text("Sign up with Google"),
                ),
              ],
            ),
          ),
    );
  }
}
