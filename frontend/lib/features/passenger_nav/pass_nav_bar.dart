import 'package:flutter/material.dart';

const Color kNavy = Color(0xFF0A2540);

class PassengerNavBar extends StatelessWidget {
  const PassengerNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final void Function(int) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: Colors.white,
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home, color: kNavy),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.search_rounded, color: kNavy),
          label: 'Search',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_taxi_outlined),
          selectedIcon: Icon(Icons.local_taxi, color: kNavy),
          label: 'Rides',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: kNavy),
          label: 'Profile',
        ),
      ],
    );
  }
}
