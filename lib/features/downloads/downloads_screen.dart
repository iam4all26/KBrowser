import 'package:flutter/material.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../models/download_record.dart';
import '../../services/download_service.dart';

/// The files downloaded in this profile. Tap a file to open it.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.profile, required this.downloads});
  final AppProfile profile;
  final DownloadService downloads;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadRecord>? _items;

  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await widget.downloads.list(widget.profile.id);
    if (mounted) setState(() => _items = l);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _open(DownloadRecord d) async {
    try {
      await KMultiProfiles.openFile(d.location, d.isUri, d.mime);
    } catch (e) {
      _toast('Could not open the file: $e');
    }
  }

  Future<void> _share(DownloadRecord d) async {
    try {
      await KMultiProfiles.shareFile(d.location, d.isUri, d.mime);
    } catch (e) {
      _toast('Could not share the file: $e');
    }
  }

  static String _size(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  IconData _icon(DownloadRecord d) {
    final m = d.mime.toLowerCase();
    final n = d.name.toLowerCase();
    if (m.startsWith('image/')) return Icons.image_outlined;
    if (m.startsWith('video/')) return Icons.movie_outlined;
    if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (m.contains('pdf') || n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.apk')) return Icons.android;
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text('Downloads: ${widget.profile.displayName}'),
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(
              tooltip: 'Clear the list',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear the list?'),
                    content: const Text('Only the list is cleared. The files stay on your phone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (ok == true) await widget.downloads.clear(widget.profile.id);
              },
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No downloads yet in this profile.', textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final d = items[i];
                    final detail = [
                      _size(d.size),
                      _date(d.createdAt),
                      if (d.inAppFolder) 'App folder',
                    ].where((s) => s.isNotEmpty).join('  |  ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Material(
                        color: context.panel,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _open(d),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: AppColors.purple, child: Icon(_icon(d), color: Colors.white)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(detail, style: TextStyle(fontSize: 12, color: context.muted)),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'open') _open(d);
                                    if (v == 'share') _share(d);
                                    if (v == 'remove') widget.downloads.remove(d.id);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'open', child: Text('Open')),
                                    PopupMenuItem(value: 'share', child: Text('Share')),
                                    PopupMenuItem(value: 'remove', child: Text('Remove from list')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
