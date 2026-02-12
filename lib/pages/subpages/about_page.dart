import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// PAGE WRAPPER
// ============================================================
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AboutDetailPage(key: ValueKey('aboutPage'));
  }
}

// ============================================================
// ABOUT DETAIL PAGE
// ============================================================
class AboutDetailPage extends StatefulWidget {
  const AboutDetailPage({super.key});

  @override
  State<AboutDetailPage> createState() => _AboutDetailPageState();
}

// ============================================================
// ANIMATION STATE
// Handles fade-in effect on page load
// ============================================================
class _AboutDetailPageState extends State<AboutDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  // ============================================================
  // INIT ANIMATION
  // ============================================================

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // PAGE LAYOUT
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.key,
      backgroundColor: Colors.transparent,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            "assets/images/crypto_logo.png",
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Text(
                        "Why Desktop Encryption Client",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "CRYPTOGRAPHY ENABLER",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "We go beyond traditional cybersecurity. We elevate threat detection and data protection to meet today’s evolving risks. "
                        "\n We believe security must be built into every organization by design \n — not added as an afterthought.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Text(
                        "Homebuilt. Globally Ready.",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "We deliver advanced solutions that power secure digital transformation. "
                        "\n By combining state-of-the-art cryptography with deep local expertise, \n we protect your data from leaks, breaches, and corruption.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 35),
                      Container(
                        height: 1,
                        color: Colors.white.withOpacity(0.3),
                        margin: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 30,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: const [
                          ContactEmailButton(),
                          NurhanLinkedIn(),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        "An demo UI @Desktop Encryption Client",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EXTERNAL LINK – WEBSITE
// ============================================================
class ContactEmailButton extends StatelessWidget {
  final String emailAddress = "nurhanmaidin@gmail.com";

  const ContactEmailButton({super.key});

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(scheme: 'mailto', path: emailAddress);

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _launchEmail,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.15),
          border: Border.all(color: Colors.white30),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.email, color: Colors.white),
            SizedBox(width: 8),
            Text(
              "Send Email",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EXTERNAL LINK – LINKEDIN
// ============================================================

class NurhanLinkedIn extends StatelessWidget {
  final String linkedInUrl = "https://www.linkedin.com/in/nurhanmarshall/";
  const NurhanLinkedIn({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => launchUrl(
        Uri.parse(linkedInUrl),
        mode: LaunchMode.externalApplication,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.15),
          border: Border.all(color: Colors.white30),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, color: Colors.white),
            SizedBox(width: 8),
            Text(
              "Connect on LinkedIn",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
