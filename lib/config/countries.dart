import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Country {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  String get displayName => '$flag  $name ($dialCode)';
}

const List<Country> countriesList = [
  Country(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
  Country(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  Country(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳'),
  Country(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
  Country(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
  Country(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
  Country(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
  Country(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
  Country(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
  Country(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭'),
  Country(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
  Country(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
  Country(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
  Country(name: 'Hong Kong', code: 'HK', dialCode: '+852', flag: '🇭🇰'),
  Country(name: 'Taiwan', code: 'TW', dialCode: '+886', flag: '🇹🇼'),
  Country(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
  Country(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  Country(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
  Country(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
  Country(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
  Country(name: 'Netherlands', code: 'NL', dialCode: '+31', flag: '🇳🇱'),
  Country(name: 'Switzerland', code: 'CH', dialCode: '+41', flag: '🇨🇭'),
  Country(name: 'Sweden', code: 'SE', dialCode: '+46', flag: '🇸🇪'),
  Country(name: 'Norway', code: 'NO', dialCode: '+47', flag: '🇳🇴'),
  Country(name: 'Denmark', code: 'DK', dialCode: '+45', flag: '🇩🇰'),
  Country(name: 'Finland', code: 'FI', dialCode: '+358', flag: '🇫🇮'),
  Country(name: 'Belgium', code: 'BE', dialCode: '+32', flag: '🇧🇪'),
  Country(name: 'Austria', code: 'AT', dialCode: '+43', flag: '🇦🇹'),
  Country(name: 'Ireland', code: 'IE', dialCode: '+353', flag: '🇮🇪'),
  Country(name: 'Poland', code: 'PL', dialCode: '+48', flag: '🇵🇱'),
  Country(name: 'Portugal', code: 'PT', dialCode: '+351', flag: '🇵🇹'),
  Country(name: 'Greece', code: 'GR', dialCode: '+30', flag: '🇬🇷'),
  Country(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
  Country(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
  Country(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦'),
  Country(name: 'Kuwait', code: 'KW', dialCode: '+965', flag: '🇰🇼'),
  Country(name: 'Bahrain', code: 'BH', dialCode: '+973', flag: '🇧🇭'),
  Country(name: 'Oman', code: 'OM', dialCode: '+968', flag: '🇴🇲'),
  Country(name: 'Israel', code: 'IL', dialCode: '+972', flag: '🇮🇱'),
  Country(name: 'Turkey', code: 'TR', dialCode: '+90', flag: '🇹🇷'),
  Country(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽'),
  Country(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
  Country(name: 'Argentina', code: 'AR', dialCode: '+54', flag: '🇦🇷'),
  Country(name: 'Colombia', code: 'CO', dialCode: '+57', flag: '🇨🇴'),
  Country(name: 'Chile', code: 'CL', dialCode: '+56', flag: '🇨🇱'),
  Country(name: 'Peru', code: 'PE', dialCode: '+51', flag: '🇵🇪'),
  Country(name: 'New Zealand', code: 'NZ', dialCode: '+64', flag: '🇳🇿'),
  Country(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
  Country(name: 'Egypt', code: 'EG', dialCode: '+20', flag: '🇪🇬'),
  Country(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬'),
  Country(name: 'Kenya', code: 'KE', dialCode: '+254', flag: '🇰🇪'),
  Country(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰'),
  Country(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩'),
  Country(name: 'Russia', code: 'RU', dialCode: '+7', flag: '🇷🇺'),
  Country(name: 'Ukraine', code: 'UA', dialCode: '+380', flag: '🇺🇦'),
  Country(name: 'Czech Republic', code: 'CZ', dialCode: '+420', flag: '🇨🇿'),
  Country(name: 'Hungary', code: 'HU', dialCode: '+36', flag: '🇭🇺'),
  Country(name: 'Romania', code: 'RO', dialCode: '+40', flag: '🇷🇴'),
];

Country getDefaultCountry() {
  return countriesList.firstWhere(
    (c) => c.code == 'PH' || c.dialCode == '+63',
    orElse: () => countriesList.first,
  );
}

void showCountryPickerModal(
  BuildContext context, {
  required Country selectedCountry,
  required ValueChanged<Country> onSelect,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _CountryPickerBottomSheet(
        selectedCountry: selectedCountry,
        onSelect: onSelect,
      );
    },
  );
}

class _CountryPickerBottomSheet extends StatefulWidget {
  final Country selectedCountry;
  final ValueChanged<Country> onSelect;

  const _CountryPickerBottomSheet({
    required this.selectedCountry,
    required this.onSelect,
  });

  @override
  State<_CountryPickerBottomSheet> createState() => _CountryPickerBottomSheetState();
}

class _CountryPickerBottomSheetState extends State<_CountryPickerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Country> _filteredCountries = countriesList;

  @override
  void initState() {
    super.initState();
    _filteredCountries = countriesList;
    _searchController.addListener(_filter);
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = countriesList;
      } else {
        _filteredCountries = countriesList.where((c) {
          return c.name.toLowerCase().contains(query) ||
              c.dialCode.toLowerCase().contains(query) ||
              c.code.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Country / Region',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.manrope(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search country name or code...',
                  hintStyle: GoogleFonts.manrope(color: Colors.grey[500], fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // Country list
          Expanded(
            child: _filteredCountries.isEmpty
                ? Center(
                    child: Text(
                      'No countries found',
                      style: GoogleFonts.manrope(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredCountries.length,
                    itemBuilder: (context, index) {
                      final country = _filteredCountries[index];
                      final isSelected = country.code == widget.selectedCountry.code &&
                          country.dialCode == widget.selectedCountry.dialCode;

                      return InkWell(
                        onTap: () {
                          widget.onSelect(country);
                          Navigator.pop(context);
                        },
                        child: Container(
                          color: isSelected ? const Color(0x1A5BBCFF) : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Text(
                                country.flag,
                                style: const TextStyle(fontSize: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF1E88E5) : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                country.dialCode,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? const Color(0xFF1E88E5) : Colors.grey[600],
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF1E88E5),
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
