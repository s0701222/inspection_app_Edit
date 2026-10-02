import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:exif/exif.dart';

void main() {
  runApp(const InspectionApp());
}

class InspectionApp extends StatelessWidget {
  const InspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inspection Record Form',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const InspectionForm(),
    );
  }
}

class ConditionItemModel {
  final String title;
  final String subtitle;
  bool isYes;
  final TextEditingController remarksController;

  ConditionItemModel({
    required this.title,
    required this.subtitle,
    this.isYes = true,
    TextEditingController? remarksController,
  }) : remarksController = remarksController ?? TextEditingController();
}

class PhotoData {
  final XFile file;
  final String photoGps;
  final String photoTime;
  final double? latitude;
  final double? longitude;

  PhotoData({
    required this.file,
    required this.photoGps,
    required this.photoTime,
    this.latitude,
    this.longitude,
  });
}

class InspectionForm extends StatefulWidget {
  const InspectionForm({super.key});

  @override
  State<InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends State<InspectionForm> {
  // Form Controllers
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _itemInspectedController = TextEditingController();
  final TextEditingController _findingsController = TextEditingController(text: 'Please refer to the photos attached');
  final TextEditingController _actionTakenController = TextEditingController(text: 'Nil');
  final TextEditingController _witnessingPartiesController = TextEditingController(text: 'Nil');

  // Date & Time
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Inspection Type
  String _inspectionType = 'General';
  final List<String> _inspectionTypes = ['General', 'Safety', 'Environmental', 'Quality'];

  // Conditions List
  final List<ConditionItemModel> _conditions = [
    ConditionItemModel(
      title: 'A. Site Safety',
      subtitle: '(Including Accident/Fire Prevention, Environment/Hygiene/First-Aid At Workplace, Manual Handling And F&IU Regulations If Applicable)',
    ),
    ConditionItemModel(
      title: 'B. Site Security/Cleanliness',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'C. Progress Against The Agreed Programme',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'D. Environmental Issue/Waste Management',
      subtitle: '',
    ),
    ConditionItemModel(
      title: 'E. Appropriate Workers With Adequate Protection',
      subtitle: '(Including Personal Protective Equipment)',
    ),
  ];

  String _locationData = 'Fetching location...';
  List<PhotoData> _photos = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermissionAndGetLocation();
  }

  // LIVE GPS: Fetches coordinates for the PDF Footer
  Future<bool> _ensureLocationPermissionAndGetLocation({bool promptSettings = false}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (promptSettings && mounted) await Geolocator.openLocationSettings();
        if (mounted) setState(() => _locationData = 'Location services disabled.');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _locationData = 'Location permissions denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (promptSettings && mounted) await Geolocator.openAppSettings();
        if (mounted) setState(() => _locationData = 'Location permissions permanently denied.');
        return false;
      } 

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null && mounted) {
        setState(() {
          String latDir = position!.latitude >= 0 ? 'N' : 'S';
          String lngDir = position!.longitude >= 0 ? 'E' : 'W';
          _locationData = '${position!.latitude.abs().toStringAsFixed(6)}°$latDir, ${position!.longitude.abs().toStringAsFixed(6)}°$lngDir';
        });
        return true;
      } else if (mounted) {
        setState(() => _locationData = 'Unable to obtain GPS location.');
        return false;
      }
    } catch (e) {
      if (mounted) setState(() => _locationData = 'Location error (Check permissions)');
      return false;
    }
    return false;
  }

  // EXIF GPS: Extracts metadata and raw coordinates from attached photos
  Future<Map<String, dynamic>> _extractPhotoExif(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);

      String? photoGps;
      String? photoTime;
      double? latVal;
      double? lngVal;

      if (data.containsKey('GPS GPSLatitude') && data.containsKey('GPS GPSLongitude')) {
        final latTag = data['GPS GPSLatitude'];
        final lngTag = data['GPS GPSLongitude'];
        final latRef = data['GPS GPSLatitudeRef']?.printable ?? 'N';
        final lngRef = data['GPS GPSLongitudeRef']?.printable ?? 'E';

        if (latTag != null && lngTag != null) {
          final List latValues = latTag.values.toList();
          final List lngValues = lngTag.values.toList();

          if (latValues.length >= 3 && lngValues.length >= 3) {
            double latDeg = _ratioToDouble(latValues[0]) + (_ratioToDouble(latValues[1]) / 60.0) + (_ratioToDouble(latValues[2]) / 3600.0);
            double lngDeg = _ratioToDouble(lngValues[0]) + (_ratioToDouble(lngValues[1]) / 60.0) + (_ratioToDouble(lngValues[2]) / 3600.0);

            if (latRef.contains('S') || latRef == 'S') latDeg = -latDeg;
            if (lngRef.contains('W') || lngRef == 'W') lngDeg = -lngDeg;

            latVal = latDeg;
            lngVal = lngDeg;

            String latDir = latDeg >= 0 ? 'N' : 'S';
            String lngDir = lngDeg >= 0 ? 'E' : 'W';

            photoGps = '${latDeg.abs().toStringAsFixed(6)}°$latDir, ${lngDeg.abs().toStringAsFixed(6)}°$lngDir';
          }
        }
      }

      if (data.containsKey('EXIF DateTimeOriginal')) {
        photoTime = data['EXIF DateTimeOriginal']?.printable;
      } else if (data.containsKey('Image DateTime')) {
        photoTime = data['Image DateTime']?.printable;
      }

      return {
        'gps': photoGps ?? 'N/A',
        'time': photoTime ?? 'N/A',
        'lat': latVal,
        'lng': lngVal,
      };
    } catch (_) {
      return {'gps': 'N/A', 'time': 'N/A', 'lat': null, 'lng': null};
    }
  }

  double _ratioToDouble(dynamic value) {
    if (value is Ratio) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0.0;
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? selectedImages = await picker.pickMultiImage();
    if (selectedImages != null && selectedImages.isNotEmpty) {
      for (var xFile in selectedImages) {
        final exif = await _extractPhotoExif(File(xFile.path));
        setState(() {
          _photos.add(PhotoData(
            file: xFile,
            photoGps: exif['gps']!,
            photoTime: exif['time']!,
            latitude: exif['lat'],
            longitude: exif['lng'],
          ));
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startDate = picked;
        else _endDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? (_startTime ?? TimeOfDay.now()) : (_endTime ?? TimeOfDay.now()),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startTime = picked;
        else _endTime = picked;
      });
    }
  }

  // PDF Generation
  Future<void> _generatePdf() async {
    if (_isGenerating) return;
    
    bool locationRetrieved = await _ensureLocationPermissionAndGetLocation(promptSettings: true);

    if (!locationRetrieved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notice: Could not acquire live GPS ($_locationData). Exporting with available metadata.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() => _isGenerating = true);

    try {
      pw.Font regularFont;
      pw.Font boldFont;

      try {
        regularFont = await PdfGoogleFonts.robotoRegular().timeout(const Duration(seconds: 5));
        boldFont = await PdfGoogleFonts.robotoBold().timeout(const Duration(seconds: 5));
      } catch (_) {
        regularFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      List<pw.MemoryImage> preloadedPdfImages = [];
      for (var item in _photos) {
        final bytes = await File(item.file.path).readAsBytes();
        preloadedPdfImages.add(pw.MemoryImage(bytes));
      }

      final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));
      
      final String startDateStr = DateFormat('dd/MM/yyyy').format(_startDate);
      final String endDateStr = DateFormat('dd/MM/yyyy').format(_endDate);
      final String startTimeStr = _startTime != null 
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}' 
          : '--:--';
      final String endTimeStr = _endTime != null 
          ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}' 
          : '--:--';
      
      final String submitTime = '${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())} HKT';

      pw.Widget buildPdfTextField(String label, String value) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(value.isEmpty ? 'Nil' : value, style: const pw.TextStyle(fontSize: 11)),
            ]
          )
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Submitted: $submitTime GPS: $_locationData', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text('OP10-1', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ]
              )
            );
          },
          build: (pw.Context context) {
            return [
              pw.Center(child: pw.Text('Inspection Record Form', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Text('Project/Contract No.: ${_projectController.text}', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Start Date: $startDateStr', style: const pw.TextStyle(fontSize: 11))),
                  pw.Expanded(child: pw.Text('End Date: $endDateStr', style: const pw.TextStyle(fontSize: 11))),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Start Time: $startTimeStr', style: const pw.TextStyle(fontSize: 11))),
                  pw.Expanded(child: pw.Text('End Time: $endTimeStr', style: const pw.TextStyle(fontSize: 11))),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Inspection Type: $_inspectionType', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 20),

              pw.Text('General Conditions', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.5),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Satisfactory', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Remarks', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    ]
                  ),
                  ..._conditions.map((cond) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(cond.title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            if (cond.subtitle.isNotEmpty) 
                              pw.Container(margin: const pw.EdgeInsets.only(top: 2), child: pw.Text(cond.subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800))),
                          ]
                        )
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Center(child: pw.Text(cond.isYes ? 'Yes' : 'No', style: const pw.TextStyle(fontSize: 10)))
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(cond.remarksController.text.isEmpty ? '' : cond.remarksController.text, style: const pw.TextStyle(fontSize: 10))
                      ),
                    ]
                  )).toList(),
                ]
              ),
              pw.SizedBox(height: 20),

              buildPdfTextField('Item Inspected:', _itemInspectedController.text),
              buildPdfTextField('Inspection Findings/Results:', _findingsController.text),
              buildPdfTextField('Action Taken:', _actionTakenController.text),
              buildPdfTextField('Other Witnessing Parties (if any):', _witnessingPartiesController.text),
              
              pw.SizedBox(height: 10),
              pw.Text('Inspected by: ________________________', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 15),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Approved by: ________________________', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Signature Date: ________________________', style: const pw.TextStyle(fontSize: 11)),
                ]
              ),
              
              if (_photos.isNotEmpty) ...[
                pw.NewPage(),
                pw.Text('Photos Attached', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: _photos.asMap().entries.map((entry) {
                    int idx = entry.key;
                    PhotoData item = entry.value;
                    final pdfImage = preloadedPdfImages[idx];

                    // Prepare Maps URL if valid GPS data exists
                    final String? mapsUrl = (item.photoGps != 'N/A' && item.latitude != null && item.longitude != null)
                        ? 'https://www.google.com/maps/search/?api=1&query=${item.latitude},${item.longitude}'
                        : null;

                    return pw.TableRow(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          height: 200,
                          alignment: pw.Alignment.center,
                          child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          alignment: pw.Alignment.topLeft,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            mainAxisAlignment: pw.MainAxisAlignment.start,
                            children: [
                              pw.Text('Photo ${idx + 1}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                              pw.SizedBox(height: 8),
                              pw.Text('Time: ${item.photoTime}', style: const pw.TextStyle(fontSize: 10)),
                              pw.SizedBox(height: 4),
                              pw.Text('GPS: ${item.photoGps}', style: const pw.TextStyle(fontSize: 10)),
                              
                              // Display raw URL directly if valid
                              if (mapsUrl != null) ...[
                                pw.SizedBox(height: 4),
                                pw.UrlLink(
                                  destination: mapsUrl,
                                  child: pw.Text(
                                    mapsUrl,
                                    style: const pw.TextStyle(
                                      fontSize: 8,
                                      color: PdfColors.blue,
                                      decoration: pw.TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ]
                          )
                        ),
                      ]
                    );
                  }).toList(),
                ),
              ]
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Inspection_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: const [
            Icon(Icons.description, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Inspection Record Form', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isGenerating ? Colors.grey : Colors.indigo,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: _isGenerating ? null : _generatePdf,
              icon: _isGenerating 
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.download, color: Colors.white, size: 16),
              label: Text(_isGenerating ? 'Processing...' : 'Generate PDF', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Project/Contract No. *', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _projectController, decoration: const InputDecoration(hintText: 'e.g. HK/2026/0042', border: OutlineInputBorder())),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectDate(context, true),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd/MM/yyyy').format(_startDate)), const Icon(Icons.calendar_today, size: 20)]),
                        ),
                      ),
                    ],
                  )
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('End Date'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectDate(context, false),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd/MM/yyyy').format(_endDate)), const Icon(Icons.calendar_today, size: 20)]),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Start Time'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(context, true),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_startTime != null ? _startTime!.format(context) : '--:--'), const Icon(Icons.access_time, size: 20)]),
                        ),
                      ),
                    ],
                  )
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('End Time'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(context, false),
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_endTime != null ? _endTime!.format(context) : '--:--'), const Icon(Icons.access_time, size: 20)]),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text('Inspection Type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _inspectionType,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: _inspectionTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
              onChanged: (val) => setState(() => _inspectionType = val!),
            ),
            const SizedBox(height: 32),

            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('General Conditions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ..._conditions.map((cond) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cond.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
                        if (cond.subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2.0), child: Text(cond.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic))),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<bool>(value: true, groupValue: cond.isYes, activeColor: Colors.indigo, visualDensity: VisualDensity.compact, onChanged: (val) => setState(() => cond.isYes = val!)),
                            const Text('Yes'),
                            const SizedBox(width: 8),
                            Radio<bool>(value: false, groupValue: cond.isYes, activeColor: Colors.indigo, visualDensity: VisualDensity.compact, onChanged: (val) => setState(() => cond.isYes = val!)),
                            const Text('No'),
                            const SizedBox(width: 12),
                            Expanded(child: SizedBox(height: 38, child: TextField(controller: cond.remarksController, decoration: InputDecoration(hintText: 'Remarks', contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)))))),
                          ],
                        ),
                        if (_conditions.last != cond) const Divider(height: 24),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Item Inspected', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _itemInspectedController, decoration: const InputDecoration(border: OutlineInputBorder()), maxLines: 4),
            const SizedBox(height: 20),

            const Text('Inspection Findings/Results', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _findingsController, decoration: const InputDecoration(border: OutlineInputBorder()), maxLines: 4),
            const SizedBox(height: 20),

            const Text('Action Taken', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _actionTakenController, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 20),

            const Text('Other Witnessing Parties (if any)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _witnessingPartiesController, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 24),

            const Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickImages,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Column(children: const [Icon(Icons.add_a_photo, size: 40, color: Colors.indigo), SizedBox(height: 8), Text('Tap to add photos', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.w500))]),
              ),
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_photos[index].file.path), fit: BoxFit.cover)),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _photos.removeAt(index)),
                          child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white70), child: const Icon(Icons.cancel, color: Colors.red)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}