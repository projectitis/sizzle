import 'dart:math';

extension MutableRectangleExt on MutableRectangle {
  void setValues(double left, double top, double width, double height) {
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
  }
}
