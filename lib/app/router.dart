import 'package:go_router/go_router.dart';

import '../features/gallery/gallery_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const GalleryScreen(),
    ),
  ],
);
