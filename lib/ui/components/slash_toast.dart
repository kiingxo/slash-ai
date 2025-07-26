import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import 'slash_text.dart';

class SlashToast {
  static showSuccess(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 2),
      description: SlashText(
        message,
        fontWeight: FontWeight.w500,
        overflow: TextOverflow.ellipsis,
      ),
      alignment: Alignment.topCenter,
      direction: TextDirection.ltr,
      animationDuration: const Duration(milliseconds: 800),
      showIcon: true,
      icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
      showProgressBar: false,
      primaryColor: Colors.greenAccent,
      backgroundColor: Color(0xff111111),
      foregroundColor: Color(0xffFFFFFF),
      borderSide: BorderSide(color: Colors.greenAccent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
      borderRadius: BorderRadius.circular(12),
    );
  }

  static showError(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 2),
      description: SlashText(
        message,
        fontWeight: FontWeight.w500,
        overflow: TextOverflow.ellipsis,
      ),
      alignment: Alignment.topCenter,
      direction: TextDirection.ltr,
      animationDuration: const Duration(milliseconds: 800),
      showIcon: true,
      icon: const Icon(Icons.error, color: Colors.redAccent),
      showProgressBar: false,
      primaryColor: Colors.redAccent,
      backgroundColor: Color(0xff111111),
      foregroundColor: Color(0xffFFFFFF),
      borderSide: BorderSide(color: Colors.redAccent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 30),
      borderRadius: BorderRadius.circular(12),
    );
  }

  static showInfo(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 2),
      description: SlashText(
        message,
        fontWeight: FontWeight.w500,
        overflow: TextOverflow.ellipsis,
      ),
      alignment: Alignment.topCenter,
      direction: TextDirection.ltr,
      animationDuration: const Duration(milliseconds: 800),
      showIcon: true,
      icon: const Icon(Icons.info, color: Colors.blueAccent),
      showProgressBar: false,
      primaryColor: Colors.blueAccent,
      backgroundColor: Color(0xff111111),
      foregroundColor: Color(0xffFFFFFF),
      borderSide: BorderSide(color: Colors.blueAccent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
      borderRadius: BorderRadius.circular(12),
    );
  }
}
