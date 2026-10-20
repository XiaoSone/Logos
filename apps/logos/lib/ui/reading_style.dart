import 'package:flutter/material.dart';

const readingAccent = Color(0xffd56b6b);

Color readingPaper(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff191b1a)
    : const Color(0xfff7f7f6);

Color readingInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffdededb)
    : const Color(0xff444444);

Color readingChrome(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff202321)
    : Colors.white;

Widget readingBackButton(BuildContext context, VoidCallback onPressed) =>
    TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: readingInk(context),
        padding: const EdgeInsets.only(left: 8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_ios_new, size: 20),
          SizedBox(width: 3),
          Text(
            '返回',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w300),
          ),
        ],
      ),
    );

Future<void> showReadingTranslation(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.check, color: readingAccent),
                title: Text('和合本 · CUVs'),
                subtitle: Text('eBible.org · 公共领域'),
              ),
              Text('其他译本与对照阅读尚未接入。'),
            ],
          ),
        ),
      ),
    );
