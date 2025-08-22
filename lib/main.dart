import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ccid/ccid.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

// Data model for storing Thai ID card information
class ThaiIdCard {
  final String idcard;
  final String thFullName;
  final String enFullName;
  final String birthDay;
  final String gender;
  final String addressrew;
  final String issueDate;
  final String expiryDate;
  final Uint8List? photo;

  final String prefixName;
  final String firstName;
  final String lastName;

  final String address;
  final String moo;
  final String soi;
  final String road;
  final String address4;
  final String tambon;
  final String amphoe;
  final String province;

  ThaiIdCard({
    this.idcard = '',
    this.thFullName = '',
    this.enFullName = '',
    this.birthDay = '',
    this.gender = '',
    this.addressrew = '',
    this.issueDate = '',
    this.expiryDate = '',
    this.photo,

    this.prefixName = '',
    this.firstName = '',
    this.lastName = '',
    this.address = '',
    this.moo = '',
    this.soi = '',
    this.road = '',
    this.address4 = '',
    this.tambon = '',
    this.amphoe = '',
    this.province = '',
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TKM Regis',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        primaryColor: Color(0xFF2D294A),
        useMaterial3: true,
        fontFamily: 'Prompt',
      ),
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
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
  int page = 0;
  Timer? _timer;
  int _start = 3;

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
      _card!.disconnect();
    }
    super.dispose();
  }

  // APDU Command สำหรับ SELECT Applet ของบัตรประชาชนไทย
  final String apduSelect = '00A4040008A000000054480001';

  // APDU Commands สำหรับอ่านข้อมูลแต่ละส่วน
  final Map<String, String> apduCommands = {
    'idcard': '80B0000402000D',
    'thFullName': '80B00011020064',
    'enFullName': '80B00075020064',
    'birthDay': '80B000D9020008',
    'gender': '80B000E1020001',
    'addressrew': '80B01579020064',
    'issueDate': '80B00167020008',
    'expiryDate': '80B0016F020008',
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
      page = 1;
    });

    CcidCard? card;
    try {
      card = await _ccidPlugin.connect(_selectedReader!);
      await card.transceive(apduSelect);
      _card = card;
      // อ่านข้อมูลที่เป็น Text ทั้งหมด
      final idcard = await _transceiveAndDecode(card, apduCommands['idcard']!);
      final thFullName = (await _transceiveAndDecode(
        card,
        apduCommands['thFullName']!,
      ))?.replaceAll('#', ' ');
      final enFullName = (await _transceiveAndDecode(
        card,
        apduCommands['enFullName']!,
      ))?.replaceAll('#', ' ');
      final dobRaw = await _transceiveAndDecode(
        card,
        apduCommands['birthDay']!,
      );
      final genderRaw = await _transceiveAndDecode(
        card,
        apduCommands['gender']!,
      );
      final addressrew = (await _transceiveAndDecode(
        card,
        apduCommands['addressrew']!,
      ))?.replaceAll('#', ' ');
      final issueDateRaw = await _transceiveAndDecode(
        card,
        apduCommands['issueDate']!,
      );
      final expireDateRaw = await _transceiveAndDecode(
        card,
        apduCommands['expiryDate']!,
      );

      // อ่านข้อมูลรูปภาพ
      final photo = await _fetchPhoto(card);

      // แยกชื่อภาษาไทย
      List<String> thNameParts =
          thFullName?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
      String prefixName = thNameParts.isNotEmpty ? thNameParts[0] : '';
      String firstName = thNameParts.length > 1 ? thNameParts[1] : '';
      String lastName =
          thNameParts.length > 2 ? thNameParts.sublist(2).join(' ') : '';

      // แยกที่อยู่
      List<String> addressParts =
          addressrew?.split(' ').map((s) => s.trim()).toList() ?? [];
      String address = addressParts.isNotEmpty ? addressParts[0] : '';
      String moo = addressParts.length > 1 ? addressParts[1] : '';
      String road = addressParts.length > 2 ? addressParts[2] : '';
      String soi = addressParts.length > 3 ? addressParts[3] : '';
      String address4 = addressParts.length > 4 ? addressParts[4] : '';
      String tambon = addressParts.length > 5 ? addressParts[5] : '';
      String amphoe = addressParts.length > 6 ? addressParts[6] : '';
      String province = addressParts.length > 7 ? addressParts[7] : '';

      if (addressParts.length > 8) {
        moo = addressParts.length > 2 ? addressParts[2] : '';
        road = addressParts.length > 3 ? addressParts[3] : '';
        soi = addressParts.length > 4 ? addressParts[4] : '';
        address4 = addressParts.length > 5 ? addressParts[5] : '';
        tambon = addressParts.length > 6 ? addressParts[6] : '';
        amphoe = addressParts.length > 7 ? addressParts[7] : '';
        province = addressParts.length > 8 ? addressParts[8] : '';
      }

      // แปลงข้อมูลให้อยู่ในรูปแบบที่อ่านง่าย
      final gender =
          genderRaw == '1' ? 'ชาย' : (genderRaw == '2' ? 'หญิง' : 'N/A');

      final birthDay = _formatDate(dobRaw);
      final issueDate = _formatDate(issueDateRaw);
      final expiryDate = _formatDate(expireDateRaw);

      setState(() {
        _idCardData = ThaiIdCard(
          idcard: idcard ?? 'N/A',
          thFullName: thFullName ?? 'N/A',
          enFullName: enFullName ?? 'N/A',
          birthDay: birthDay,
          gender: gender,
          addressrew: addressrew ?? 'N/A',
          issueDate: issueDate,
          expiryDate: expiryDate,
          photo: photo,

          prefixName: prefixName,
          firstName: firstName,
          lastName: lastName,
          address: address,
          moo: moo,
          soi: soi,
          road: road,
          address4: address4,
          tambon: tambon,
          amphoe: amphoe,
          province: province,
        );
        page = 2;
      });
    } catch (e) {
      _showErrorDialog('ไม่สามารถอ่านข้อมูลในบัตรได้: $e');
    } finally {
      if (card != null) {
        try {
          await card.disconnect().timeout(const Duration(seconds: 0));
          _card = null;
          setState(() {
            page = 0;
          });
        } catch (e) {}
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

  void launchURL(url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('เกิดข้อผิดพลาด'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed:
                    () => {
                      Navigator.of(context).pop(),
                      setState(() {
                        page = 0;
                      }),
                    },
                child: const Text('ตกลง'),
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
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
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
      extendBodyBehindAppBar: true,
      // appBar: AppBar(
      //   // backgroundColor: Color(0xFF2D294A),
      //   flexibleSpace: Container(

      //   ),
      // ),
      body: Container(
        // เว้นระยะให้ไม่โดน title ของ AppBar
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 22, 20, 38),
              Color.fromARGB(255, 22, 20, 38),
              Color.fromARGB(255, 22, 20, 38),
              Color.fromARGB(255, 22, 20, 38),
              Color(0xFF2D294A),
              Color(0xFF645c90),
            ], // ไล่สี
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          // color: Colors.white,
        ),
        // padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.only(
                top: kToolbarHeight,
                left: 10,
                right: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'TKM Regis',
                        style: TextStyle(
                          fontSize: 35,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Image.asset(
                        'assets/logo-full-c2.png',
                        width: 30,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${_readers.length > 0 ? _readers[0].toString() : 'ยังไม่ได้เชื่อมต่อเครื่องอ่านบัตร'}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        iconSize: 20,
                        color: Colors.white,
                        onPressed: _refreshReaders,
                        tooltip: 'Refresh Readers',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Expanded(
            //   child: Container(
            //     child: Row(
            //       children: [
            //         // Expanded(
            //         //   child:
            //         //   // DropdownButton<String>(
            //         //   //   isExpanded: true,
            //         //   //   value: _selectedReader,
            //         //   //   hint: const Text('Select a reader'),
            //         //   //   items:
            //         //   //       _readers.map((String value) {
            //         //   //         return DropdownMenuItem<String>(
            //         //   //           value: value,
            //         //   //           child: Text(value, overflow: TextOverflow.ellipsis),
            //         //   //         );
            //         //   //       }).toList(),
            //         //   //   onChanged: (value) {
            //         //   //     setState(() {
            //         //   //       _selectedReader = value;
            //         //   //     });
            //         //   //   },
            //         //   // ),
            //         // ),

            //       ],
            //     ),
            //   ),
            // ),
            // const SizedBox(height: 16),
            // !_isReading && _idCardData == null
            if (page == 0)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    color: Colors.white,
                  ),
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: _readers.length > 0 ? _readThaiIdCard : null,
                        child: Container(
                          width: 200,
                          padding: EdgeInsets.symmetric(
                            vertical: 30,
                            horizontal: 20,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _readers.length > 0
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.4),
                                spreadRadius: 0,
                                blurRadius: 4,
                                offset: const Offset(
                                  1,
                                  3,
                                ), // changes position of shadow
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'ดูข้อมูลในบัตร',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // ElevatedButton.icon(
                  //   icon: const Icon(Icons.credit_card),
                  //   onPressed: _isReading ? null : _readThaiIdCard,
                  //   label: const Text('Read ID Card'),
                  //   style: ElevatedButton.styleFrom(
                  //     padding: const EdgeInsets.symmetric(vertical: 16),
                  //     textStyle: const TextStyle(fontSize: 16),
                  //   ),
                  // ),
                ),
              ),
            // const Divider(),
            // _isReading
            if (page == 1)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    color: Colors.white,
                  ),
                  child: Center(
                    child: const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  width: double.infinity,
                ),
              ),
            // _idCardData != null
            if (page == 2)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    color: Colors.white,
                  ),
                  width: double.infinity,
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
                                border: Border.all(
                                  color: Theme.of(context).primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _idCardData!.photo!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      _buildInfoRow('เลขบัตรประชาชน:', _idCardData!.idcard),
                      _buildInfoRow('ชื่อ-สกุล:', _idCardData!.thFullName),
                      _buildInfoRow(
                        'ชื่อ-สกลุ(ภาษาอังกฤษ):',
                        _idCardData!.enFullName,
                      ),
                      _buildInfoRow('เพศ:', _idCardData!.gender),
                      _buildInfoRow('วัน/เดือน/ปีเกิด:', _idCardData!.birthDay),
                      _buildInfoRow('ที่อยู่:', _idCardData!.addressrew),
                      _buildInfoRow('วันที่ออกบัตร:', _idCardData!.issueDate),
                      _buildInfoRow('วันหมดอายุบัตร:', _idCardData!.expiryDate),
                      SizedBox(height: 50),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final Map<String, String> queryParams = {
                                'idcard': _idCardData!.idcard,
                                'prefixName': _idCardData!.prefixName,
                                // 'thFullName': _idCardData!.thFullName,
                                // 'enFullName': _idCardData!.enFullName,
                                'firstName': _idCardData!.firstName,
                                'lastName': _idCardData!.lastName,
                                // 'first_name_en':
                                //     _idCardData!.enFullName
                                //         .split(' ')
                                //         .first, // สมมติว่าชื่ออังกฤษไม่มีคำนำหน้า
                                // 'last_name_en': _idCardData!.enFullName.split(' ').last,
                                'birthDay': DateFormat('yyyy-MM-dd').format(
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).parseStrict(_idCardData!.birthDay),
                                ),
                                // 'addressrew': _idCardData!.addressrew,
                                // 'gender': _idCardData!.gender,
                                'address': _idCardData!.address,
                                'moo': _idCardData!.moo,
                                'soi': _idCardData!.soi,
                                'road': _idCardData!.road,
                                'address4': _idCardData!.address4,
                                'tambon': _idCardData!.tambon,
                                'amphoe': _idCardData!.amphoe,
                                'province': _idCardData!.province,
                                'issueDate': DateFormat('yyyy-MM-dd').format(
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).parseStrict(_idCardData!.issueDate),
                                ),
                                'expiryDate': DateFormat('yyyy-MM-dd').format(
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).parseStrict(_idCardData!.expiryDate),
                                ),
                              };

                              final queryString = queryParams.entries
                                  .map(
                                    (entry) =>
                                        '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
                                  )
                                  .join('&');

                              // final uri =
                              //     'https://gateway.we-builds.com/tkm/#/register-form?$queryString';
                              final url = Uri.parse(
                                'https://gateway.we-builds.com/tkm/#/register-form?$queryString',
                              );
                              print('-----${url.toString()}');
                              launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );

                              // เรียก launchUrl
                              if (await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              )) {
                                // เมื่อเปิดได้แล้ว ค่อย setState
                                _timer = Timer.periodic(Duration(seconds: 1), (
                                  timer,
                                ) {
                                  print(timer.isActive);
                                  if (_start == 0) {
                                    timer.cancel();
                                    setState(() {
                                      page = 0;
                                    });
                                  } else {
                                    setState(() {
                                      _start--;
                                    });
                                  }
                                });
                              } else {
                                // ถ้าเปิดไม่ได้ ก็จัดการ error
                                setState(() {
                                  page = 0;
                                });
                              }
                              // launchURL(url);
                              // Navigator.push(
                              //   context,
                              //   MaterialPageRoute(
                              //     builder: (context) => WebPageScreen(url: uri.toString()),
                              //   ),
                              // );
                            },

                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.4),
                                    spreadRadius: 0,
                                    blurRadius: 4,
                                    offset: const Offset(
                                      1,
                                      3,
                                    ), // changes position of shadow
                                  ),
                                ],
                              ),
                              child: Text(
                                'เปิดหน้าเว็บ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _idCardData = null;
                                _isReading = false;
                                page = 0;
                              });
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: Theme.of(context).primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.4),
                                    spreadRadius: 0,
                                    blurRadius: 4,
                                    offset: const Offset(
                                      1,
                                      3,
                                    ), // changes position of shadow
                                  ),
                                ],
                              ),
                              child: Text(
                                'ย้อนกลับ',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class WebPageScreen extends StatefulWidget {
  final String url;
  const WebPageScreen({super.key, required this.url});
  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // สำหรับ Android: ต้องใช้ PlatformView
    // สำหรับ iOS: ต้องเพิ่ม permission
    _controller =
        WebViewController()
          ..setJavaScriptMode(
            JavaScriptMode.unrestricted,
          ) // อนุญาตให้รัน JavaScript
          ..setBackgroundColor(
            const Color(0x00000000),
          ) // ตั้งค่าพื้นหลังโปร่งใส
          ..setNavigationDelegate(
            NavigationDelegate(
              // ถูกเรียกเมื่อหน้าเว็บเริ่มโหลด
              onPageStarted: (String url) {
                setState(() {
                  _isLoading = true;
                });
              },
              // ถูกเรียกเมื่อหน้าเว็บโหลดเสร็จสมบูรณ์
              onPageFinished: (String url) {
                setState(() {
                  _isLoading = false;
                });
              },
              // ถูกเรียกเมื่อการโหลดล้มเหลว
              onWebResourceError: (WebResourceError error) {
                // สามารถแสดงหน้าจอ Error ที่นี่ได้
                debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
            ''');
              },
            ),
          )
          // โหลด URL ที่ส่งเข้ามา
          ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ลงทะเบียนสมาชิกพรรค')),
      body: Stack(
        children: [
          // Widget สำหรับแสดงผลหน้าเว็บ
          WebViewWidget(controller: _controller),

          // แสดง Loading Indicator ขณะที่หน้าเว็บกำลังโหลด
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
