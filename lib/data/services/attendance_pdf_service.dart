// lib/data/services/attendance_pdf_service.dart
//
// Generates a professional attendance report PDF.
// Uses the `pdf` Flutter package (pub.dev/packages/pdf).
// Share/save with the `printing` package (pub.dev/packages/printing).
//
// Add to pubspec.yaml:
//   pdf: ^3.10.0
//   printing: ^5.12.0

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/attendance_model.dart';

class AttendancePdfService {
  // ── Brand colours (match AppTheme) ──────────────────────────────────────
  static const _primary = PdfColor.fromInt(0xFF6C63FF);
  static const _primaryDark = PdfColor.fromInt(0xFF0F0F1A);
  static const _success = PdfColor.fromInt(0xFF10B981);
  static const _error = PdfColor.fromInt(0xFFEF4444);
  static const _warning = PdfColor.fromInt(0xFFF59E0B);
  static const _textPrimary = PdfColor.fromInt(0xFF1A1A2E);
  static const _textMuted = PdfColor.fromInt(0xFF94A3B8);
  static const _headerBg = PdfColor.fromInt(0xFF1E1B4B);
  static const _rowAlt = PdfColor.fromInt(0xFFF8F7FF);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _white = PdfColors.white;

  // ── Colour helpers ───────────────────────────────────────────────────────

  /// Blends [color] toward white by [factor] (0.0 = white, 1.0 = original).
  /// Replaces the unsupported `PdfColor * double` operator.
  static PdfColor _tint(PdfColor color, double factor) {
    return PdfColor(
      color.red + (1.0 - color.red) * (1.0 - factor),
      color.green + (1.0 - color.green) * (1.0 - factor),
      color.blue + (1.0 - color.blue) * (1.0 - factor),
    );
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Builds and returns the PDF bytes.
  ///
  /// [records]      – attendance list for [reportDate]
  /// [reportDate]   – the day the report covers
  /// [downloadedBy] – name of the admin/manager generating the report
  static Future<Uint8List> generateAttendanceReport({
    required List<AttendanceModel> records,
    required DateTime reportDate,
    required String downloadedBy,
  }) async {
    final pdf = pw.Document(
      title: 'Attendance Report',
      author: downloadedBy,
      subject: 'Daily Attendance Report',
    );

    // Sort: present first (with login time), then absent
    final sorted = [...records]
      ..sort((a, b) {
        if (a.loginTime != null && b.loginTime == null) return -1;
        if (a.loginTime == null && b.loginTime != null) return 1;
        if (a.loginTime != null && b.loginTime != null) {
          return a.loginTime!.compareTo(b.loginTime!);
        }
        return a.employeeName.compareTo(b.employeeName);
      });

    // Because the table is wide we use landscape A4
    const pageFormat = PdfPageFormat.a4;
    final landscapeFormat = pageFormat.landscape;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: landscapeFormat,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => _buildHeader(ctx, reportDate, downloadedBy, records),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          _buildSummaryRow(records),
          pw.SizedBox(height: 20),
          _buildTable(sorted),
          pw.SizedBox(height: 12),
          _buildLegend(),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Header ────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    pw.Context ctx,
    DateTime reportDate,
    String downloadedBy,
    List<AttendanceModel> records,
  ) {
    final now = DateTime.now();
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Brand block
          pw.Container(
            width: 44,
            height: 44,
            decoration: pw.BoxDecoration(
              color: _primary,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Center(
              child: pw.Text(
                'A',
                style: pw.TextStyle(
                  color: _white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ATTENDX',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _primaryDark,
                    letterSpacing: 3,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Daily Attendance Report',
                  style: pw.TextStyle(fontSize: 11, color: _textMuted),
                ),
              ],
            ),
          ),
          // Meta block (right-aligned)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _metaRow('Report Date', _fmtDate(reportDate)),
              _metaRow('Downloaded', '${_fmtDate(now)}  ${_fmtTime(now)}'),
              _metaRow('Generated By', downloadedBy),
              _metaRow('Total Records', '${records.length}'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label:  ',
              style: pw.TextStyle(
                fontSize: 9,
                color: _textMuted,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
            pw.TextSpan(
              text: value,
              style: pw.TextStyle(
                fontSize: 9,
                color: _textPrimary,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary row ───────────────────────────────────────────────────────────

  static pw.Widget _buildSummaryRow(List<AttendanceModel> records) {
    final present = records.where((r) => r.status == 'present').length;
    final absent = records.where((r) => r.status == 'absent').length;
    final incomplete = records.where((r) => r.status == 'incomplete').length;

    return pw.Row(
      children: [
        _summaryCard('Total', records.length.toString(), _primary),
        pw.SizedBox(width: 10),
        _summaryCard('Present', present.toString(), _success),
        pw.SizedBox(width: 10),
        _summaryCard('Absent', absent.toString(), _error),
        pw.SizedBox(width: 10),
        _summaryCard('Incomplete', incomplete.toString(), _warning),
      ],
    );
  }

  static pw.Widget _summaryCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: pw.BoxDecoration(
          color: _tint(color, 0.1),
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _tint(color, 0.3), width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _textMuted)),
          ],
        ),
      ),
    );
  }

  // ── Main table ────────────────────────────────────────────────────────────

  static pw.Widget _buildTable(List<AttendanceModel> records) {
    // Column definitions: [header, flex-weight, alignment]
    const columns = [
      ('Emp. ID', 10, pw.Alignment.centerLeft),
      ('Employee Name', 16, pw.Alignment.centerLeft),
      ('Check In', 9, pw.Alignment.center),
      ('Check Out', 9, pw.Alignment.center),
      ('Break Out', 9, pw.Alignment.center),
      ('Break In', 9, pw.Alignment.center),
      ('Lunch Out', 9, pw.Alignment.center),
      ('Lunch In', 9, pw.Alignment.center),
      ('Work Hours', 9, pw.Alignment.center),
      ('Break Dur.', 9, pw.Alignment.center),
      ('Status', 9, pw.Alignment.center),
    ];

    pw.Widget cell(
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
      pw.TextStyle? style,
      PdfColor? bg,
      bool isHeader = false,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        color: bg,
        alignment: align,
        child: pw.Text(
          text,
          style:
              style ??
              pw.TextStyle(
                fontSize: isHeader ? 8 : 7.5,
                fontWeight: isHeader
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: isHeader ? _white : _textPrimary,
              ),
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
        ),
      );
    }

    // Header row
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: _headerBg),
      children: columns
          .map((c) => cell(c.$1, align: c.$3, isHeader: true))
          .toList(),
    );

    // Data rows
    final dataRows = <pw.TableRow>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      final isAlt = i.isEven;
      final rowBg = isAlt ? _rowAlt : _white;

      // Safely extract first break & first lunch
      final b = r.breaks.isNotEmpty ? r.breaks.first : null;
      final l = r.lunches.isNotEmpty ? r.lunches.first : null;

      // Work hours computed correctly (net = gross - breaks - lunches)
      final workHrs = _computeNetWorkHours(r);
      final breakDur = _formatDuration(r.totalBreakHours + r.totalLunchHours);

      // Status pill colour
      PdfColor statusColor;
      switch (r.status) {
        case 'present':
          statusColor = _success;
          break;
        case 'absent':
          statusColor = _error;
          break;
        default:
          statusColor = _warning;
      }

      dataRows.add(
        pw.TableRow(
          children: [
            // Emp ID — use employeeCode if exists in name (not in model here,
            // we use the document id prefix for brevity)
            cell(_shortId(r.employeeId), bg: rowBg),
            cell(
              r.employeeName,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            cell(
              _fmtTimeOpt(r.loginTime),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: _success,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            cell(
              _fmtTimeOpt(r.logoutTime),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: _error,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            // Break Out = when employee left for break (breakOut field)
            cell(
              _fmtTimeOpt(b?.breakOut),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColor.fromInt(0xFFFF9800),
              ),
            ),
            // Break In = when employee returned from break (breakIn field)
            cell(
              _fmtTimeOpt(b?.breakIn),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColor.fromInt(0xFFFF9800),
              ),
            ),
            // Lunch Out = when employee left for lunch (lunchOut field)
            cell(
              _fmtTimeOpt(l?.lunchOut),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColor.fromInt(0xFF9C27B0),
              ),
            ),
            // Lunch In = when employee returned from lunch (lunchIn field)
            cell(
              _fmtTimeOpt(l?.lunchIn),
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: PdfColor.fromInt(0xFF9C27B0),
              ),
            ),
            cell(
              workHrs,
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _primary,
              ),
            ),
            cell(
              breakDur,
              align: pw.Alignment.center,
              bg: rowBg,
              style: pw.TextStyle(fontSize: 7.5, color: _textMuted),
            ),
            // Status pill
            pw.Container(
              color: rowBg,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 6,
              ),
              alignment: pw.Alignment.center,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: _tint(statusColor, 0.15),
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(
                    color: _tint(statusColor, 0.4),
                    width: 0.5,
                  ),
                ),
                child: pw.Text(
                  r.status.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: {
        for (int i = 0; i < columns.length; i++)
          i: pw.FlexColumnWidth(columns[i].$2.toDouble()),
      },
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.5),
        bottom: pw.BorderSide(color: _border, width: 0.5),
        left: pw.BorderSide(color: _border, width: 0.5),
        right: pw.BorderSide(color: _border, width: 0.5),
        top: pw.BorderSide(color: _border, width: 0.5),
      ),
      children: [headerRow, ...dataRows],
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  static pw.Widget _buildLegend() {
    return pw.Row(
      children: [
        pw.Text(
          'Note: ',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _textMuted,
          ),
        ),
        _legendItem('Break Out/In', PdfColor.fromInt(0xFFFF9800)),
        pw.SizedBox(width: 12),
        _legendItem('Lunch Out/In', PdfColor.fromInt(0xFF9C27B0)),
        pw.SizedBox(width: 12),
        _legendItem(
          'Work Hrs = (Check Out - Check In) - Breaks - Lunch',
          _primary,
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          '-- = Not recorded',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
      ],
    );
  }

  static pw.Widget _legendItem(String label, PdfColor color) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _textMuted)),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by AttendX · Confidential',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  static String _fmtTimeOpt(DateTime? dt) => dt != null ? _fmtTime(dt) : '--';

  static String _shortId(String id) {
    // Show last 8 chars of UUID for readability
    if (id.length > 8) return '...${id.substring(id.length - 8)}';
    return id;
  }

  /// Net working hours = (logout - login) minus all break & lunch durations.
  static String _computeNetWorkHours(AttendanceModel r) {
    if (r.loginTime == null) return '--';
    final end = r.logoutTime ?? DateTime.now();
    var totalMinutes = end.difference(r.loginTime!).inMinutes;

    for (final b in r.breaks) {
      if (b.breakIn != null) {
        totalMinutes -= b.breakIn!.difference(b.breakOut).inMinutes;
      }
    }
    for (final l in r.lunches) {
      if (l.lunchIn != null) {
        totalMinutes -= l.lunchIn!.difference(l.lunchOut).inMinutes;
      }
    }

    if (totalMinutes < 0) totalMinutes = 0;
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static String _formatDuration(double hours) {
    final totalMinutes = (hours * 60).round();
    if (totalMinutes <= 0) return '--';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }
}
