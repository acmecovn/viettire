import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final first = cameras.first;
  final store = await AppStore.load();
  runApp(MyApp(camera: first, store: store));
}

// =================== CONFIG ===================
const String uploadWebhookUrl =
    "https://n8n.vnigo.sbs/webhook-test/e5b0fe30-1e33-41fb-828a-c887d31629e4"; // POST (multipart)
const String pollWebhookUrl =
    "https://n8n.vnigo.sbs/webhook-test/results45e4rsf4gd5sdg45as4r78sfg"; // GET ?device_id=...

// NEW: 3 webhook làm việc với Spreadsheet
const String sheetAppendUrl =
    "https://n8n.vnigo.sbs/webhook-test/sheet-append4545431431"; // POST JSON
const String sheetListUrl =
    "https://n8n.vnigo.sbs/webhook-test/sheet-list464132154"; // GET ?device_id=...
const String sheetExportClearUrl =
    "https://n8n.vnigo.sbs/webhook-test/sheet-export-clear5271215454"; // POST JSON

const String submitTableWebhookUrl =
    "https://n8n.vnigo.sbs/webhook-test/submit-tablemfgdjfghlk6546df4g654dfg"; // (giữ nếu bạn cần)


const String basicUser = "ton";
const String basicPass = "Ton@12345";

// ============== DATA MODELS + STORE ===========
class RowItem {
  int index;      // stt
  String serial;  // seri
  RowItem({required this.index, required this.serial});

  Map<String, dynamic> toJson() => {'index': index, 'serial': serial};

  factory RowItem.fromJson(Map<String, dynamic> j) =>
      RowItem(index: j['index'] ?? j['stt'], serial: j['serial'] ?? j['seri'] ?? '');
}


class AppStore extends ChangeNotifier {
  static const _prefsKey = 'viettire_camera_store_v1';

  String deviceId;
  String productName;
  List<RowItem> rows;

  Timer? _pollTimer;

  AppStore({
    required this.deviceId,
    this.productName = '',
    List<RowItem>? rows,
  }) : rows = rows ?? [];

  static Future<AppStore> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_prefsKey);
    if (s != null) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return AppStore(
        deviceId: j['deviceId'],
        productName: j['productName'] ?? '',
        rows: (j['rows'] as List<dynamic>? ?? [])
            .map((e) => RowItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    // Tạo deviceId bền vững lần đầu
    final devId = const Uuid().v4();
    final store = AppStore(deviceId: devId);
    await store.save();
    return store;
  }


Future<void> _appendToSheet(List<String> serials) async {
  if (serials.isEmpty) return;
  final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));

  final body = {
    "device_id": deviceId,
    "product_name": productName, // size vỏ
    "items": serials.map((s) => {
      "seri": s,
      // "stt": ... // có thể để n8n tự đánh số
    }).toList(),
  };

  try {
    final res = await http.post(
      Uri.parse(sheetAppendUrl),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Basic $basic",
      },
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      // optional: log lỗi
    }
  } catch (_) {
    // optional: log lỗi
  }
}

Future<void> syncFromSheet() async {
  final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));
  final uri = Uri.parse("$sheetListUrl?device_id=$deviceId");
  try {
    final res = await http.get(uri, headers: {"Authorization": "Basic $basic"});
    if (res.statusCode != 200 || res.body.isEmpty) return;

    final j = jsonDecode(res.body);
    final pn = (j is Map) ? (j['product_name']?.toString() ?? '') : '';
    if (pn.isNotEmpty) productName = pn;

    final List<RowItem> newRows = [];
    if (j is Map && j['rows'] is List) {
      for (final r in (j['rows'] as List)) {
        if (r is Map) {
          final stt = (r['stt'] ?? r['index']) ?? 0;
          final seri = (r['seri'] ?? r['serial'])?.toString() ?? '';
          if (seri.trim().isNotEmpty) {
            newRows.add(RowItem(index: stt is int ? stt : int.tryParse(stt.toString()) ?? 0, serial: seri.trim()));
          }
        }
      }
    }
    replaceRows(newRows);
  } catch (_) {
    // im lặng
  }
}

Future<Map<String, dynamic>?> exportAndClearSheet() async {
  final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));
  final body = {"device_id": deviceId};
  try {
    final res = await http.post(
      Uri.parse(sheetExportClearUrl),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Basic $basic",
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 200 && res.body.isNotEmpty) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
  } catch (_) {}
  return null;
}


  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'deviceId': deviceId,
      'productName': productName,
      'rows': rows.map((e) => e.toJson()).toList(),
    });
    await sp.setString(_prefsKey, data);
  }

  void setProductName(String name) {
    productName = name;
    save();
    notifyListeners();
  }

  void setRowSerial(int index, String serial) {
    final i = rows.indexWhere((e) => e.index == index);
    if (i >= 0) {
      rows[i].serial = serial;
    } else {
      rows.add(RowItem(index: index, serial: serial));
      rows.sort((a, b) => a.index.compareTo(b.index));
    }
    save();
    notifyListeners();
  }

  void appendSerials(List<String> serials) {
    int next = rows.isEmpty ? 1 : (rows.map((e) => e.index).reduce((a, b) => a > b ? a : b) + 1);
    for (final s in serials) {
      rows.add(RowItem(index: next++, serial: s));
    }
    save();
    notifyListeners();
  }

  void replaceRows(List<RowItem> newRows) {
    rows = newRows..sort((a, b) => a.index.compareTo(b.index));
    save();
    notifyListeners();
  }

  Future<void> reset() async {
    productName = '';
    rows = [];
    await save();
    notifyListeners();
  }

  Future<void> startPolling() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());
    // Trigger ngay 1 lần
    unawaited(_pollOnce());
  }

  Future<void> stopPolling() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
  try {
    final uri = Uri.parse("$pollWebhookUrl?device_id=$deviceId");
    final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));
    final res = await http.get(uri, headers: {"Authorization": "Basic $basic"});

    if (res.statusCode != 200 || res.body.isEmpty) return;

    final decoded = jsonDecode(res.body);

    // Thu thập seri từ nhiều kiểu payload khác nhau:
    // 1) Mảng [{ output: { device_id, product_name, seri } }, ...]
    // 2) { items: ["S123","S124",...] } hoặc { items: [{serial:"S123"}, ...] }
    // 3) ["S123","S124", ...] (mảng string thuần)
    final List<String> serials = [];

    // Helper: push nếu là chuỗi không rỗng
    void addIfValid(String? s) {
      if (s != null && s.trim().isNotEmpty && s.toLowerCase() != 'null') {
        serials.add(s.trim());
      }
    }

    if (decoded is List) {
      // Trường hợp mảng các object có key "output"
      for (final el in decoded) {
        if (el is Map && el['output'] is Map) {
          final out = Map<String, dynamic>.from(el['output']);
          final did = out['device_id']?.toString();
          if (did == deviceId) {
            // Cập nhật product_name nếu app đang rỗng
            final pn = out['product_name']?.toString();
            if ((productName.isEmpty) && pn != null && pn.isNotEmpty) {
              setProductName(pn);
            }
            addIfValid(out['seri']?.toString());
          }
        } else if (el is String) {
          // fallback: mảng string
          addIfValid(el);
        } else if (el is Map && el['serial'] is String) {
          addIfValid(el['serial'] as String);
        }
      }
    } else if (decoded is Map && decoded['items'] is List) {
      // Trường hợp { items: [...] }
      for (final it in decoded['items']) {
        if (it is String) addIfValid(it);
        if (it is Map && it['serial'] is String) addIfValid(it['serial'] as String);
      }
    } else if (decoded is String) {
      addIfValid(decoded);
    }

    if (serials.isEmpty) {
      // Dù AI không trả thêm gì mới, vẫn sync từ sheet (để UI luôn bám theo sheet)
      await syncFromSheet();
      return;
    }

    // Đẩy list serials mới lên sheet (n8n sẽ tự loại trùng/đánh stt)
    await _appendToSheet(serials);

    // Sau khi append, đọc lại sheet để render UI
    await syncFromSheet();

  } catch (_) {
    // im lặng, poll tiếp lần sau
  }
}

}

// =================== APP WIDGETS ===================
class MyApp extends StatefulWidget {
  final CameraDescription camera;
  final AppStore store;
  const MyApp({super.key, required this.camera, required this.store});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.store.startPolling();
  }

  @override
  void dispose() {
    widget.store.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_tab == 0 ? "Dữ liệu" : "Chụp ảnh"),
            ),
            body: _tab == 0
                ? DataTab(store: widget.store)
                : CameraTab(camera: widget.camera, store: widget.store),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _tab,
              onTap: (i) => setState(() => _tab = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.table_chart), label: "Dữ liệu"),
                BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Chụp ảnh"),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DataTab extends StatefulWidget {
  final AppStore store;
  const DataTab({super.key, required this.store});

  @override
  State<DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<DataTab> {
  final _nameCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtl.text = widget.store.productName;
    _nameCtl.addListener(() => widget.store.setProductName(_nameCtl.text));
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _submitTable() async {
  // 1) Export + Clear trên n8n/Spreadsheet
  final exported = await widget.store.exportAndClearSheet();

  // 2) (tuỳ chọn) gửi JSON export đến API khác để lưu chính thức
  // final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));
  // await http.post(Uri.parse(submitTableWebhookUrl), headers: {
  //   "Content-Type": "application/json",
  //   "Authorization": "Basic $basic",
  // }, body: jsonEncode(exported));

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(exported != null ? "Đã export & clear sheet" : "Export thất bại")),
    );
  }

  // 3) Reset app state và refresh UI
  await widget.store.reset();
  _nameCtl.text = '';
  // 4) Sync lại từ sheet (lúc này sheet đã trống)
  await widget.store.syncFromSheet();
}


  @override
  Widget build(BuildContext context) {
    final rows = widget.store.rows;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _nameCtl,
            decoration: const InputDecoration(
              labelText: "Tên sản phẩm",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text("Chưa có số seri. Hãy chụp ảnh hoặc đợi AI trả kết quả."))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      leading: Text("${r.index}"),
                      title: TextFormField(
                        initialValue: r.serial,
                        onChanged: (v) => widget.store.setRowSerial(r.index, v),
                        decoration: const InputDecoration(
                          hintText: "Số seri",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Xoá dữ liệu?"),
                        content: const Text("Thao tác này sẽ xoá tên sản phẩm và toàn bộ seri."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Huỷ")),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Reset")),
                        ],
                      ),
                    );
                    if (ok == true) await widget.store.reset();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reset"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: rows.isEmpty && widget.store.productName.isEmpty ? null : _submitTable,
                  icon: const Icon(Icons.send),
                  label: const Text("Gửi đi"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CameraTab extends StatefulWidget {
  final CameraDescription camera;
  final AppStore store;
  const CameraTab({super.key, required this.camera, required this.store});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  late CameraController _controller;
  late Future<void> _initFuture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _initFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _deviceModel() async {
    final info = DeviceInfoPlugin();
    final android = await info.androidInfo;
    return "${android.manufacturer} ${android.model}";
  }

  Future<void> _captureAndSend() async {
    try {
      await _initFuture;
      final XFile xfile = await _controller.takePicture();

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Xác nhận ảnh'),
          content: Image.file(File(xfile.path)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Chụp lại')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gửi')),
          ],
        ),
      );
      if (ok != true) return;

      setState(() => _sending = true);

      final now = DateTime.now();
      final filename = "img_${now.toIso8601String().replaceAll(":", "-")}.jpg";
      final model = await _deviceModel();
      final basic = base64Encode(utf8.encode("$basicUser:$basicPass"));

      final req = http.MultipartRequest("POST", Uri.parse(uploadWebhookUrl));
      req.headers["Authorization"] = "Basic $basic";

      req.files.add(await http.MultipartFile.fromPath(
        "file",
        xfile.path,
        filename: filename,
        contentType: MediaType("image", "jpeg"),
      ));

      // Truyền thêm metadata để n8n biết đẩy về device nào
      req.fields["device_id"] = widget.store.deviceId;
      req.fields["product_name"] = widget.store.productName;
      req.fields["captured_at"] = now.toIso8601String();
      req.fields["device_model"] = model;

      final resp = await req.send();
      await resp.stream.drain(); // không hiển thị status text theo yêu cầu

      setState(() => _sending = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Đã gửi ảnh • HTTP ${resp.statusCode}")),
      );
    } catch (e) {
      setState(() => _sending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi gửi ảnh: $e")),
      );
    }
  }

@override
Widget build(BuildContext context) {
  return FutureBuilder(
    future: _initFuture,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return Stack(
        children: [
          CameraPreview(_controller),

          // Nút chụp ảnh ở góc phải dưới
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: _sending ? null : _captureAndSend,
              child: const Icon(Icons.camera_alt),
            ),
          ),

          // Trạng thái đang gửi
          if (_sending)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    },
  );
}

}
