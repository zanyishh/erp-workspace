// Dimensions match the original billing app, including its paginated roll output.
enum InvoicePaper {
  a4('A4', 210, 297),
  a5('A5', 148, 210),
  receipt58('58 mm receipt', 58, 297),
  receipt80('80 mm receipt', 80, 297);

  const InvoicePaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm, heightMm;
  bool get isReceipt => this == receipt58 || this == receipt80;
}
