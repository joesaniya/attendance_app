// lib/widgets/offline_indicator.dart
import 'package:flutter/material.dart';
import '../core/services/network_service.dart';
import '../core/theme/app_theme.dart';

class OfflineIndicator extends StatelessWidget {
  final Widget child;
  const OfflineIndicator({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NetworkService().onNetworkChange,
      initialData: true,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? true;
        
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              child,
              if (!isOnline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: AppTheme.errorColor.withOpacity(0.95),
                      child: const Text(
                        'Offline Mode - Changes will sync when online',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
