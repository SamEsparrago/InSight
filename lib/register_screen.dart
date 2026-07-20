import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // To access MainNavigationScreen

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // this form key is used to easily check if all the text fields are filled out correctly later
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorMessage = null;
      _isLoading = true; // turns on the loading spinner!
    });

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // 1. Create Firebase User
      // this actually asks firebase to create a brand new account with this email and password
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Set Display Name
      // firebase normally just stores the email and password, so we manually attach the user's name to their profile
      if (userCredential.user != null) {
        await userCredential.user!.updateDisplayName(name);
      }

      if (!mounted) return;
      
      // Navigate to Main screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (e.code == 'email-already-in-use') {
          _errorMessage = 'The email account already exists.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'The email address is invalid.';
        } else if (e.code == 'weak-password') {
          _errorMessage = 'The password is too weak.';
        } else {
          _errorMessage = e.message ?? 'Registration failed.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF5D6AF2);
    const Color inputBackground = Color(0xFF1A1A24);
    const Color textColor = Colors.white;
    const Color subtitleColor = Colors.white54;
    const Color backgroundColor = Color(0xFF0F0F13);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // HEADER
                  const Text(
                    'INSIGHT',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CREATE STAFF ACCOUNT',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      color: subtitleColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  // ERROR MESSAGE
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // NAME FIELD
                  const Text('Full Name', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: inputBackground,
                      hintText: 'e.g. John Doe',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      prefixIcon: const Icon(Icons.person_outline, color: subtitleColor),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    // this validator checks if the field is empty when they press sign up.
                    // if it is empty, it stops them and shows this error message in red!
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your name';
                      }
                      return null; // returning null means there is no error!
                    },
                  ),
                  const SizedBox(height: 20),

                  // EMAIL FIELD
                  const Text('Email Address', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: inputBackground,
                      hintText: 'e.g. johndoe@gmail.com',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      prefixIcon: const Icon(Icons.email_outlined, color: subtitleColor),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // PASSWORD FIELD
                  const Text('Password', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: inputBackground,
                      hintText: '..........',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      prefixIcon: const Icon(Icons.lock_outline, color: subtitleColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: subtitleColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (val.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // CONFIRM PASSWORD FIELD
                  const Text('Confirm Password', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    style: const TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: inputBackground,
                      hintText: '..........',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      prefixIcon: const Icon(Icons.lock_outline, color: subtitleColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                          color: subtitleColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (val) {
                      if (val != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // REGISTER BUTTON
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'SIGN UP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // GO BACK TO LOGIN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Already have an account? ',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Log In',
                          style: TextStyle(
                            color: primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
