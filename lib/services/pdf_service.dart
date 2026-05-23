import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/quotation.dart';
import '../models/sale_transaction.dart';
import 'package:intl/intl.dart';

class PdfService {
  static Future<void> generateAndShareQuotation(Quotation quotation) async {
    final pdf = await _generateDocument(
      title: 'QUOTATION',
      id: quotation.id,
      customerName: quotation.customerName,
      customerPhone: quotation.customerPhone,
      agentName: quotation.agentName,
      agentTitle: quotation.agentTitle,
      items: quotation.items,
      totalAmount: quotation.totalAmount,
      validUntil: quotation.validUntil,
      notes: quotation.notes,
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Quotation_${quotation.customerName?.replaceAll(' ', '_') ?? 'Quote'}.pdf',
    );
  }

  static Future<void> generateAndShareInvoice(SaleTransaction transaction) async {
    final pdf = await _generateDocument(
      title: 'TAX INVOICE',
      id: transaction.id,
      customerName: transaction.customerName,
      customerPhone: null, // Phone not in SaleTransaction but could be added if needed
      agentName: transaction.agentName,
      agentTitle: transaction.agentTitle,
      items: transaction.items,
      totalAmount: transaction.amount,
      amountPaid: transaction.amountPaid,
      paymentMethod: transaction.paymentMethod,
      notes: transaction.notes,
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Invoice_${transaction.customerName?.replaceAll(' ', '_') ?? 'Inv'}.pdf',
    );
  }

  static Future<pw.Document> _generateDocument({
    required String title,
    required String id,
    String? customerName,
    String? customerPhone,
    required String agentName,
    required String agentTitle,
    required List<SaleItem> items,
    required double totalAmount,
    double? amountPaid,
    String? paymentMethod,
    DateTime? validUntil,
    String? notes,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();

    pw.Widget logo;
    try {
      final logoImage = pw.MemoryImage(
        (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List(),
      );
      logo = pw.Image(logoImage, height: 60, fit: pw.BoxFit.contain);
    } catch (e) {
      logo = pw.Text('BizPOS', style: pw.TextStyle(font: boldFont, fontSize: 28, color: PdfColors.cyan900));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    logo,
                    pw.SizedBox(height: 5),
                    pw.Text('Smart Solutions for Business', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 32, color: PdfColors.cyan900)),
                    pw.Container(height: 2, width: 150, color: PdfColors.cyan900),
                    pw.SizedBox(height: 5),
                    pw.Text('Ref: #${id.substring(0, 8).toUpperCase()}', style: pw.TextStyle(font: boldFont, fontSize: 12)),
                    pw.Text('Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 40),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BILL TO:', style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.cyan900)),
                        pw.SizedBox(height: 8),
                        pw.Text(customerName ?? 'Valued Customer', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                        if (customerPhone != null) pw.Text('Phone: $customerPhone', style: pw.TextStyle(font: font, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('FROM:', style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.cyan900)),
                        pw.SizedBox(height: 8),
                        pw.Text(agentName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.black)),
                        pw.Text(agentTitle, style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.cyan700)),
                        pw.SizedBox(height: 4),
                        if (validUntil != null) pw.Text('Valid Until: ${DateFormat('dd MMM yyyy').format(validUntil)}', style: pw.TextStyle(font: font, fontSize: 11)),
                        if (paymentMethod != null) pw.Text('Payment: $paymentMethod', style: pw.TextStyle(font: font, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.TableHelper.fromTextArray(
              border: null,
              headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan900),
              cellHeight: 30,
              cellStyle: pw.TextStyle(font: font, fontSize: 10),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
              headerAlignment: pw.Alignment.center,
              headers: ['Product Details', 'Qty', 'Unit Price', 'Total Amount'],
              data: items.map<List<String>>((SaleItem item) => [
                item.productName,
                item.quantity.toString(),
                '₹ ${item.price.toStringAsFixed(2)}',
                '₹ ${item.total.toStringAsFixed(2)}',
              ]).toList(),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 20),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const pw.BoxDecoration(color: PdfColors.cyan900, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text('Grand Total: ', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.white)),
                            pw.Text('₹ ${totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.white)),
                          ],
                        ),
                      ),
                      if (amountPaid != null) ...[
                        pw.SizedBox(height: 8),
                        pw.Text('Amount Paid: ₹ ${amountPaid.toStringAsFixed(2)}', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
                        pw.Text('Balance Due: ₹ ${(totalAmount - amountPaid).toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.red)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 40),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (notes != null && notes.isNotEmpty) ...[
                        pw.Text('NOTES / TERMS:', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.cyan900)),
                        pw.SizedBox(height: 5),
                        pw.Text(notes, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey800)),
                      ],
                      pw.SizedBox(height: 20),
                      pw.Text('Terms & Conditions:', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.cyan900)),
                      pw.Bullet(text: 'Prices are inclusive of all taxes.', style: pw.TextStyle(font: font, fontSize: 8)),
                      pw.Bullet(text: 'Goods once sold cannot be returned.', style: pw.TextStyle(font: font, fontSize: 8)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 40),
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 20),
                      pw.Container(height: 60, width: double.infinity, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 1, style: pw.BorderStyle.dashed)))),
                      pw.SizedBox(height: 8),
                      pw.Text('Authorized Signature', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                      pw.Text('$agentName ($agentTitle)', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.cyan900, thickness: 1),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Thank you for your business!', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                  pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8)),
                ],
              ),
            ],
          );
        }
      ),
    );
    return pdf;
  }
}
