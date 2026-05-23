import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final double maxWidth;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.maxWidth = 1200,
  });

  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < 650;
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 650 && MediaQuery.of(context).size.width < 1100;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= 1100;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              return desktop ?? tablet ?? mobile;
            } else if (constraints.maxWidth >= 650) {
              return tablet ?? mobile;
            } else {
              return mobile;
            }
          },
        ),
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int crossAxisCountMobile;
  final int crossAxisCountTablet;
  final int crossAxisCountDesktop;
  final double childAspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 16.0,
    this.runSpacing = 16.0,
    this.crossAxisCountMobile = 1,
    this.crossAxisCountTablet = 2,
    this.crossAxisCountDesktop = 4,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        if (constraints.maxWidth >= 1100) {
          crossAxisCount = crossAxisCountDesktop;
        } else if (constraints.maxWidth >= 650) {
          crossAxisCount = crossAxisCountTablet;
        } else {
          crossAxisCount = crossAxisCountMobile;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: runSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}
