# Flutter N8N Image Uploader

This simple Flutter project captures an image and sends it with form data as JSON to an n8n webhook.

## Usage

1. Replace the placeholder webhook URL in `lib/main.dart` with your n8n webhook endpoint.
2. Run the app on a device or emulator.
3. Enter a name and description, capture an image, then tap **Send** to post the data.

The app encodes the image to Base64 and posts a JSON payload containing the text fields and image data.
