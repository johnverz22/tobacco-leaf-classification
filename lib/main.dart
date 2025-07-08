import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(TobaccoClassifierApp());
}

class TobaccoClassifierApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tobacco Leaf Classifier',
      theme: ThemeData(primarySwatch: Colors.green),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _imageFile;
  String _resultText = "Please upload or capture an image.";
  bool _loading = false;

  // ✅ Replace with your current ngrok endpoint
  final String apiUrl = "https://46ca1bde69ed.ngrok-free.app/predict";

  final ImagePicker _picker = ImagePicker();

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _resultText = "Processing...";
      _loading = true;
    });

    await _sendToServer(_imageFile!);
  }

  Future<void> _sendToServer(File imageFile) async {
    try {
      var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseData.body);
        setState(() {
          _resultText = "Prediction: ${data['prediction']}\nConfidence: ${data['confidence']}";
        });
      } else {
        setState(() {
          _resultText = "Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _resultText = "Error: ${e.toString()}";
      });
    }

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Tobacco Leaf Classifier"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                border: Border.all(color: Colors.grey),
              ),
              child: _imageFile != null
                  ? Image.file(_imageFile!, fit: BoxFit.cover)
                  : Center(child: Text("No image selected")),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.gallery),
                  icon: Icon(Icons.photo_library),
                  label: Text("Gallery"),
                ),
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.camera),
                  icon: Icon(Icons.camera_alt),
                  label: Text("Camera"),
                ),
              ],
            ),
            SizedBox(height: 20),
            _loading
                ? CircularProgressIndicator()
                : Text(
              _resultText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
