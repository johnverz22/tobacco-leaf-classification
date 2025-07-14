import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(TobaccoClassifierApp());
}

class TobaccoClassifierApp extends StatelessWidget {
  const TobaccoClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leaf Identifier',
      theme: ThemeData(
        primarySwatch: Colors.green,
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: Colors.black,
      ),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  File? _imageFile;
  String _resultText = "";
  String _confidenceText = "";
  bool _loading = false;
  bool _hasResult = false;
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final String apiUrl = "https://e90a28ec54a7.ngrok-free.app/predict";
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _loading = true;
      _hasResult = false;
    });

    await _sendToServer(_imageFile!);
  }

  Future<void> _sendToServer(File imageFile) async {
    try {
      var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseData.body);
        
        // Safe confidence parsing
        double confidenceValue = 0.0;
        String confidenceDisplay = "N/A";
        
        if (data['confidence'] != null) {
          try {
            // Try to parse as double first
            if (data['confidence'] is double) {
              confidenceValue = data['confidence'];
            } else if (data['confidence'] is int) {
              confidenceValue = data['confidence'].toDouble();
            } else if (data['confidence'] is String) {
              confidenceValue = double.parse(data['confidence']);
            }
            
            // If confidence is already a percentage (>1), don't multiply by 100
            if (confidenceValue > 1) {
              confidenceDisplay = "${confidenceValue.toStringAsFixed(1)}%";
            } else {
              confidenceDisplay = "${(confidenceValue * 100).toStringAsFixed(1)}%";
            }
          } catch (e) {
            print("Confidence parsing error: $e");
            confidenceDisplay = data['confidence'].toString();
          }
        }
        
        setState(() {
          _resultText = data['prediction'] ?? 'Unknown';
          _confidenceText = confidenceDisplay;
          _hasResult = true;
        });
        _fadeController.forward();
        _slideController.forward();
      } else {
        setState(() {
          _resultText = "Analysis failed";
          _confidenceText = "Server error ${response.statusCode}";
          _hasResult = true;
        });
        _fadeController.forward();
        _slideController.forward();
      }
    } catch (e) {
      setState(() {
        _resultText = "Connection error";
        _confidenceText = "Check your network";
        _hasResult = true;
      });
      _fadeController.forward();
      _slideController.forward();
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _resetToCamera() {
    setState(() {
      _imageFile = null;
      _hasResult = false;
      _loading = false;
    });
    _fadeController.reset();
    _slideController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Content
          _imageFile == null ? _buildCameraView() : _buildResultView(),
          
          // Top App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                bottom: 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _imageFile != null
                      ? GestureDetector(
                          onTap: _resetToCamera,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                      : Container(width: 36),
                  Text(
                    'Leaf Identifier',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(width: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1a1a1a),
            Color(0xFF2d2d2d),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spacer(),
          
          // Camera Icon
          Container(
            padding: EdgeInsets.all(40),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          
          SizedBox(height: 30),
          
          Text(
            'Identify Tobacco Leaves',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          SizedBox(height: 10),
          
          Text(
            'Capture or select an image to analyze',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          
          Spacer(),
          
          // Action Buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => _getImage(ImageSource.gallery),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => _getImage(ImageSource.camera),
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isPrimary ? Color(0xFF4CAF50) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isPrimary ? Color(0xFF4CAF50) : Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : Colors.white.withOpacity(0.9),
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    return Stack(
      children: [
        // Full screen image background
        Container(
          width: double.infinity,
          height: double.infinity,
          child: _imageFile != null
              ? Image.file(
                  _imageFile!,
                  fit: BoxFit.cover,
                )
              : Container(color: Colors.grey[900]),
        ),
        
        // Bottom sheet overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              child: _loading
                  ? _buildLoadingState()
                  : _hasResult
                      ? _buildResultState()
                      : _buildInitialState(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
            strokeWidth: 3,
          ),
          SizedBox(height: 20),
          Text(
            'Analyzing leaf...',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            size: 48,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'Image loaded',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Processing will start automatically',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Color(0xFF4CAF50),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildResultState() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Result Header
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _resultText.contains('error') || _resultText.contains('failed') 
                          ? Colors.red.withOpacity(0.1)
                          : Color(0xFF4CAF50).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _resultText.contains('error') || _resultText.contains('failed')
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _resultText.contains('error') || _resultText.contains('failed')
                          ? Colors.red
                          : Color(0xFF4CAF50),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    _resultText.contains('error') || _resultText.contains('failed')
                        ? 'Analysis Failed'
                        : 'Analysis Complete',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 30),
              
              // Classification Result
              _buildResultCard(
                title: 'Classification',
                value: _resultText.isNotEmpty ? _resultText : 'No result',
                icon: Icons.eco,
                color: _resultText.contains('error') || _resultText.contains('failed')
                    ? Colors.red
                    : Color(0xFF4CAF50),
              ),
              
              SizedBox(height: 20),
              
              // Confidence Level
              _buildResultCard(
                title: 'Confidence Level',
                value: _confidenceText.isNotEmpty ? _confidenceText : 'N/A',
                icon: Icons.analytics,
                color: Color(0xFF2196F3),
              ),
              
              Spacer(),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildSecondaryButton(
                      label: 'Try Again',
                      onTap: _resetToCamera,
                    ),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: _buildPrimaryButton(
                      label: 'New Image',
                      onTap: () => _getImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}