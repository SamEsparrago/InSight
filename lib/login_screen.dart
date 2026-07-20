import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // To access MainNavigationScreen
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // controllers are like little listeners that grab whatever the user types into the text boxes
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // this toggles if the password shows dots or actual text
  bool _obscurePassword = true;
  
  // when this is true, we show the loading spinner circle on the button!
  bool _isLoading = false;
  
  // if something goes wrong, we store the error message here to show to the user
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final email = _usernameController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please enter both email and password.';
        });
        return;
      }

      // here is the actual magic that logs you in via firebase!
      // we tell firebase to sign the user in using the email and password they typed
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // if the phone navigated away while waiting, we stop here to prevent crashes
      if (!mounted) return;
      
      // if successful, we replace this login screen with the main dashboard screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // Provide user-friendly error messages based on common Firebase codes
        if (e.code == 'user-not-found') {
          _errorMessage = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'Wrong password provided.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'The email address is badly formatted.';
        } else {
          _errorMessage = e.message ?? 'Authentication failed.';
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
    // Colors matching the image
    const Color primaryBlue = Color(0xFF5D6AF2);
    const Color inputBackground = Color(0xFF1A1A24);
    const Color textColor = Colors.white;
    const Color subtitleColor = Colors.white54;
    const Color backgroundColor = Color(0xFF0F0F13);

    // scaffold gives us the background of the screen
    return Scaffold(
      backgroundColor: backgroundColor,
      // safearea prevents things from overlapping with the top notch of the phone
      body: SafeArea(
        // customscrollview lets us have a screen that scrolls if the keyboard pops up, 
        // but stays normally sized if it's not needed.
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                child: Column(
                  children: [
                    // TOP SPACER
                    const SizedBox(height: 40),
                    
                    // HEADER
                    const Text(
                      'INSIGHT',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4.0,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'STAFF LOGIN',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: subtitleColor,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // ICON CIRCLE
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryBlue.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.remove_red_eye_outlined,
                          color: textColor,
                          size: 32,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 48),

                    // ERROR MESSAGE
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),

                    // USERNAME FIELD
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Email Address',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      style: const TextStyle(color: textColor),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: inputBackground,
                        hintText: 'e.g. admin@gmail.com',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        prefixIcon: const Icon(Icons.person_outline, color: subtitleColor),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // PASSWORD FIELD
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Password',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: textColor),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: inputBackground,
                        hintText: '..........',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        prefixIcon: const Icon(Icons.lock_outline, color: subtitleColor),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // SHOW PASSWORD
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: !_obscurePassword,
                            activeColor: primaryBlue,
                            side: const BorderSide(color: subtitleColor),
                            onChanged: (val) {
                              setState(() {
                                _obscurePassword = !(val ?? false);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Show password',
                          style: TextStyle(color: subtitleColor, fontSize: 13),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // LOGIN BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        // if we are loading, we disable the button (null), otherwise we run the _login function
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          elevation: 0,
                        ),
                        // this decides what shows inside the button: a loading circle, or the text 'LOG IN'
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator( // this is the spinning loading circle!
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'LOG IN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // FORGOT PASSWORD
                    TextButton(
                      onPressed: () async {
                        final email = _usernameController.text.trim();
                        if (email.isEmpty) {
                          setState(() => _errorMessage = 'Enter your email first, then tap Forgot Password.');
                          return;
                        }
                        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                        if (!mounted) return;
                        setState(() => _errorMessage = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password reset email sent!'))
                        );
                      },
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: primaryBlue.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // SIGN UP LINK
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: subtitleColor, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            );
                          },
                          child: const Text(
                             'Sign Up',
                            style: TextStyle(
                              color: primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // PUSH EVERYTHING ELSE UP
                    const Spacer(),

                    // FOOTER
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 16),
                    const Text(
                      'SIDC COOPMART — SORO-SORO IBABA',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '01 — LOGIN',
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
