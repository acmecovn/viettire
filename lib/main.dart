import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ImageCapturePage(),
    );
  }
}

class ImageCapturePage extends StatefulWidget {
  const ImageCapturePage({super.key});

  @override
  State<ImageCapturePage> createState() => _ImageCapturePageState();
}

class _ImageCapturePageState extends State<ImageCapturePage> {
  final _picker = ImagePicker();
  XFile? _image;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  Future<void> _captureImage() async {
    final image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _image = image;
      });
    }
  }

  Future<void> _sendData() async {
    if (_image == null) return;

    final bytes = await _image!.readAsBytes();
    final base64Image = base64Encode(bytes);

    final body = jsonEncode({
      'name': _nameController.text,
      'description': _descController.text,
      'image': base64Image,
    });

    final url = Uri.parse('https://your-n8n-webhook.url/webhook');
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture & Send')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: _image != null
                    ? Image.file(File(_image!.path))
                    : const Placeholder(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _captureImage,
                  child: const Text('Capture'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _sendData,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
