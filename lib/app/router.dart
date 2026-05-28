import 'package:go_router/go_router.dart';

import '../features/gallery/gallery_screen.dart';
import '../features/viewer/viewer_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const GalleryScreen(),
    ),
    GoRoute(
      path: '/viewer',
      builder: (_, __) => const ViewerScreen(),
    ),
  ],
);
