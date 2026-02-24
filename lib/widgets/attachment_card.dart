import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../models/attachment.dart';
import '../services/odoo_session_manager.dart';

class AttachmentCard extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const AttachmentCard({
    super.key,
    required this.attachment,
    required this.onDelete,
    required this.onView,
  });

  IconData _getFileIcon(String? mimetype, String name) {
    final lowerMime = (mimetype ?? '').toLowerCase();
    final lowerName = name.toLowerCase();
    bool contains(String s) => lowerMime.contains(s);

    if (contains('pdf') || lowerName.endsWith('.pdf')) {
      return HugeIcons.strokeRoundedPdf02;
    }
    if (contains('image') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.webp')) {
      return HugeIcons.strokeRoundedImage02;
    }
    if (contains('word') ||
        lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx')) {
      return HugeIcons.strokeRoundedDoc02;
    }
    if (contains('excel') ||
        lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx')) {
      return HugeIcons.strokeRoundedXls02;
    }
    if (contains('powerpoint') ||
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx')) {
      return HugeIcons.strokeRoundedPpt02;
    }
    if (contains('zip') ||
        contains('compressed') ||
        lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar')) {
      return HugeIcons.strokeRoundedZip02;
    }
    return HugeIcons.strokeRoundedAiFile;
  }

  String _formatDate(dynamic createDate) {
    final dateFormat = DateFormat('MMM dd, yyyy hh:mm a');

    if (createDate is DateTime) {
      return dateFormat.format(createDate);
    } else if (createDate is String) {
      try {
        final parsedDate = DateTime.parse(createDate);
        return dateFormat.format(parsedDate);
      } catch (e) {
        return '-';
      }
    } else {
      return '-';
    }
  }

  String _formatDescription(dynamic description) {
    if (description is String) {
      final trimmed = description.trim();
      return trimmed.isEmpty ? '-' : trimmed;
    }

    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String desc = _formatDescription(attachment.description);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: isDark ? 4 : 4,
      color: isDark ? Colors.grey[800] : Colors.white,
      shadowColor: isDark
          ? Colors.black.withOpacity(0.3)
          : Colors.grey.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _AttachmentThumbnail(
              attachment: attachment,
              isDark: isDark,
              fallbackIcon: _getFileIcon(attachment.mimetype, attachment.name),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      letterSpacing: 0.2,
                      color: isDark
                          ? Colors.white.withOpacity(0.95)
                          : Colors.grey[900],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(attachment.createDate),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.1,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  if (desc != '-' && desc.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.remove_red_eye_outlined,
                  size: 22,
                  color: isDark ? Colors.grey[300] : Colors.grey[600],
                ),
                onPressed: onView,
                tooltip: 'View attachment',
                splashRadius: 20,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
              ),
              child: IconButton(
                icon: Icon(
                  HugeIcons.strokeRoundedDelete02,
                  size: 22,
                  color: isDark ? Colors.red[300] : Colors.red[500],
                ),
                onPressed: onDelete,
                tooltip: 'Delete attachment',
                splashRadius: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  final Attachment attachment;
  final bool isDark;
  final IconData fallbackIcon;

  const _AttachmentThumbnail({
    required this.attachment,
    required this.isDark,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final baseDecoration = BoxDecoration(
      color: isDark ? Colors.grey[700] : Colors.grey[100],
      borderRadius: BorderRadius.circular(10),
      border: isDark
          ? Border.all(color: Colors.grey[600]!.withOpacity(0.3))
          : null,
    );

    if (!attachment.isImage || !attachment.isViewable) {
      return Container(
        width: 56,
        height: 56,
        decoration: baseDecoration,
        alignment: Alignment.center,
        child: Icon(
          fallbackIcon,
          size: 26,
          color: isDark ? Colors.white.withOpacity(0.9) : Colors.grey[700],
        ),
      );
    }

    return FutureBuilder<OdooSessionModel?>(
      future: OdooSessionManager.getCurrentSession(),
      builder: (context, snapshot) {
        final session = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 56,
            height: 56,
            decoration: baseDecoration,
            alignment: Alignment.center,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.white70 : Colors.grey,
                ),
              ),
            ),
          );
        }

        final relativeUrl = attachment.getDownloadUrl();
        if (session == null || relativeUrl == null) {
          return Container(
            width: 56,
            height: 56,
            decoration: baseDecoration,
            alignment: Alignment.center,
            child: Icon(
              fallbackIcon,
              size: 26,
              color: isDark ? Colors.white.withOpacity(0.9) : Colors.grey[700],
            ),
          );
        }

        final fullUrl = relativeUrl.startsWith('http')
            ? relativeUrl
            : '${session.serverUrl}${relativeUrl.startsWith('/') ? '' : '/'}$relativeUrl';

        return Container(
          width: 56,
          height: 56,
          decoration: baseDecoration,
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            fullUrl,
            headers: {'Cookie': 'session_id=${session.sessionId}'},
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) {
              return Container(
                color: isDark ? Colors.grey[700] : Colors.grey[100],
                alignment: Alignment.center,
                child: Icon(
                  fallbackIcon,
                  size: 26,
                  color: isDark
                      ? Colors.white.withOpacity(0.9)
                      : Colors.grey[700],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
