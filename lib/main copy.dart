import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ccid/ccid.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

// Data model for storing Thai ID card information
class ThaiIdCard {
  final String cid;
  final String thFullName;
  final String enFullName;
  final String dob;
  final String gender;
  final String address;
  final String issueDate;
  final String expireDate;
  final Uint8List? photo;

  ThaiIdCard({
    this.cid = '',
    this.thFullName = '',
    this.enFullName = '',
    this.dob = '',
    this.gender = '',
    this.address = '',
    this.issueDate = '',
    this.expireDate = '',
    this.photo,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thai ID Card Reader',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _ccidPlugin = Ccid();
  String? _selectedReader;
  List<String> _readers = [];
  bool _isReading = false;
  ThaiIdCard? _idCardData;
  CcidCard? _card;

  @override
  void initState() {
    super.initState();
    _refreshReaders();
  }

  @override
  void dispose() {
    // 2. เพิ่มเมธอด dispose เพื่อดักเก็บกวาดก่อนที่หน้าจอจะถูกทำลาย
    // นี่คือการรับประกันว่าจะมีการปิดการเชื่อมต่อเสมอ
    if (_card != null) {
      print("Disconnecting card from dispose() to prevent resource leak.");
      _card!.disconnect();
    }
    super.dispose();
  }

  // APDU Command สำหรับ SELECT Applet ของบัตรประชาชนไทย
  final String apduSelect = '00A4040008A000000054480001';

  // APDU Commands สำหรับอ่านข้อมูลแต่ละส่วน
  final Map<String, String> apduCommands = {
    'cid': '80B0000402000D',
    'thFullName': '80B00011020064',
    'enFullName': '80B00075020064',
    'dob': '80B000D9020008',
    'gender': '80B000E1020001',
    'address': '80B01579020064',
    'issueDate': '80B00167020008',
    'expireDate': '80B0016F020008',
  };

  final List<String> photoApduCommands = [
    '80B0017B0200FF',
    '80B0027A0200FF',
    '80B003790200FF',
    '80B004780200FF',
    '80B005770200FF',
    '80B006760200FF',
    '80B007750200FF',
    '80B008740200FF',
    '80B009730200FF',
    '80B00A720200FF',
    '80B00B710200FF',
    '80B00C700200FF',
    '80B00D6F0200FF',
    '80B00E6E0200FF',
    '80B00F6D0200FF',
    '80B0106C0200FF',
    '80B0116B0200FF',
    '80B0126A0200FF',
    '80B013690200FF',
    '80B014680200FF',
  ];

  Future<void> _refreshReaders() async {
    try {
      final readers = await _ccidPlugin.listReaders();
      setState(() {
        _readers = readers;
        _selectedReader = readers.isNotEmpty ? readers[0] : null;
      });
    } catch (e) {
      _showErrorDialog('Could not list readers: $e');
    }
  }

  Future<String?> _transceiveAndDecode(CcidCard card, String commandHex) async {
    await card.transceive(commandHex);
    final getResponseCommand = '00C00000' + commandHex.substring(12);
    final responseHex = await card.transceive(getResponseCommand);
    if (responseHex == null || responseHex.isEmpty) return null;
    final responseBytes = _hexResponseToBytes(responseHex);
    return (await CharsetConverter.decode('TIS-620', responseBytes)).trim();
  }

  // ฟังก์ชันพิเศษสำหรับอ่านรูปภาพซึ่งมีขนาดใหญ่และต้องอ่านเป็นส่วนๆ
  Future<Uint8List?> _fetchPhoto(CcidCard card) async {
    List<int> photoBytes = [];
    // วนลูปตามชุดคำสั่งรูปภาพที่ถูกต้อง 20 คำสั่ง
    for (final command in photoApduCommands) {
      await card.transceive(command);

      // คำนวณ Le (ความยาวที่ต้องการ) จาก 2 byte สุดท้ายของ command
      String le = command.substring(command.length - 2);
      String getResponseCommand = '00C00000' + le;

      final responseHex = await card.transceive(getResponseCommand);

      if (responseHex != null) {
        photoBytes.addAll(_hexResponseToBytes(responseHex));
      }
    }
    // ตรวจสอบว่ามีข้อมูลรูปภาพหรือไม่ (บางครั้งอาจคืนค่าว่าง)
    if (photoBytes.isEmpty || photoBytes.every((b) => b == 0)) {
      return null;
    }
    return Uint8List.fromList(photoBytes);
  }

  Future<void> _readThaiIdCard() async {
    if (_selectedReader == null) {
      _showErrorDialog('Please select a card reader.');
      return;
    }

    setState(() {
      _isReading = true;
      _idCardData = null;
    });

    CcidCard? card;
    try {
      card = await _ccidPlugin.connect(_selectedReader!);
      await card.transceive(apduSelect);
      _card = card;
      // อ่านข้อมูลที่เป็น Text ทั้งหมด
      final cid = await _transceiveAndDecode(card, apduCommands['cid']!);
      final thFullName = (await _transceiveAndDecode(
        card,
        apduCommands['thFullName']!,
      ))?.replaceAll('#', ' ');
      final enFullName = (await _transceiveAndDecode(
        card,
        apduCommands['enFullName']!,
      ))?.replaceAll('#', ' ');
      final dobRaw = await _transceiveAndDecode(card, apduCommands['dob']!);
      final genderRaw = await _transceiveAndDecode(
        card,
        apduCommands['gender']!,
      );
      final address = (await _transceiveAndDecode(
        card,
        apduCommands['address']!,
      ))?.replaceAll('#', ' ');
      final issueDateRaw = await _transceiveAndDecode(
        card,
        apduCommands['issueDate']!,
      );
      final expireDateRaw = await _transceiveAndDecode(
        card,
        apduCommands['expireDate']!,
      );

      // อ่านข้อมูลรูปภาพ
      final photo = await _fetchPhoto(card);

      // แปลงข้อมูลให้อยู่ในรูปแบบที่อ่านง่าย
      final gender =
          genderRaw == '1' ? 'ชาย' : (genderRaw == '2' ? 'หญิง' : 'N/A');

      final dob = _formatDate(dobRaw);
      final issueDate = _formatDate(issueDateRaw);
      final expireDate = _formatDate(expireDateRaw);

      setState(() {
        _idCardData = ThaiIdCard(
          cid: cid ?? 'N/A',
          thFullName: thFullName ?? 'N/A',
          enFullName: enFullName ?? 'N/A',
          dob: dob,
          gender: gender,
          address: address ?? 'N/A',
          issueDate: issueDate,
          expireDate: expireDate,
          photo: photo,
        );
      });
    } catch (e) {
      print('Error reading card: $e');
      _showErrorDialog('Error reading card: $e');
    } finally {
      if (card != null) {
        await card.disconnect().timeout(const Duration(seconds: 2));
        _card = null;
      }
      setState(() {
        _isReading = false;
      });
    }
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.length != 8) return 'N/A';
    final yearBE = int.tryParse(rawDate.substring(0, 4)) ?? 0;
    final yearCE = yearBE - 543; // แปลง พ.ศ. เป็น ค.ศ.
    final month = rawDate.substring(4, 6);
    final day = rawDate.substring(6, 8);
    return '$day/$month/$yearCE';
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Uint8List _hexResponseToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '');
    if (hex.length >= 4) {
      hex = hex.substring(0, hex.length - 4);
    }
    return Uint8List.fromList(
      List.generate(
        hex.length ~/ 2,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thai ID Card Reader')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedReader,
                    hint: const Text('Select a reader'),
                    items:
                        _readers.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedReader = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshReaders,
                  tooltip: 'Refresh Readers',
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.credit_card),
                onPressed: _isReading ? null : _readThaiIdCard,
                label: const Text('Read ID Card'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            if (_isReading)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            if (_idCardData != null)
              Expanded(
                child: ListView(
                  children: [
                    if (_idCardData!.photo != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Center(
                          child: Container(
                            width: 150,
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.memory(
                              _idCardData!.photo!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    _buildInfoRow('Citizen ID:', _idCardData!.cid),
                    _buildInfoRow('Thai Name:', _idCardData!.thFullName),
                    _buildInfoRow('English Name:', _idCardData!.enFullName),
                    _buildInfoRow('Gender:', _idCardData!.gender),
                    _buildInfoRow('Date of Birth:', _idCardData!.dob),
                    _buildInfoRow('Address:', _idCardData!.address),
                    _buildInfoRow('Issue Date:', _idCardData!.issueDate),
                    _buildInfoRow('Expire Date:', _idCardData!.expireDate),
                  ],
                ),
              ),
            if (_idCardData != null)
              ElevatedButton(
                child: Text('เปิดหน้าเว็บ'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => WebPageScreen()),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key});
  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    // สำหรับ Android: ต้องใช้ PlatformView
    // สำหรับ iOS: ต้องเพิ่ม permission
    _controller =
        WebViewController()
          ..loadRequest(Uri.parse('https://gateway.we-builds.com/tkm/#/register-form')); // เปลี่ยน URL ได้
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ลงทะเบียนสมาชิกพรรค')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
