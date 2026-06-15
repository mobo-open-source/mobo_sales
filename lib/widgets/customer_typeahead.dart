import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:convert';
import '../models/contact.dart';
import '../services/customer_service.dart';
import '../utils/app_theme.dart';

class CustomerTypeAhead extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool isDark;
  final ValueChanged<Contact> onCustomerSelected;
  final VoidCallback? onClear;
  final String? Function(String?)? validator;

  const CustomerTypeAhead({
    required this.controller,
    required this.labelText,
    required this.isDark,
    required this.onCustomerSelected,
    this.onClear,
    this.hintText,
    this.validator,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        TypeAheadField<Contact>(
          controller: controller,
          // Flip the suggestions box upward when there isn't enough room below
          // (otherwise fields low on the screen open their options off-screen,
          // hidden behind the keyboard / bottom bar).
          autoFlipDirection: true,
          constraints: const BoxConstraints(maxHeight: 320),
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              validator: validator,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xff000000),
              ),
              decoration: InputDecoration(
                hintText: hintText ?? 'Search customers...',
                hintStyle: GoogleFonts.manrope(
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                  fontSize: 15,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedUser,
                    color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
                    size: 18,
                  ),
                ),
                suffixIcon: controller.text.isNotEmpty && onClear != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: onClear,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowDown01,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xff7F7F7F),
                          size: 16,
                        ),
                      ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xffF8FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            );
          },
          suggestionsCallback: (pattern) async {
            // Reuse the exact query the (working) customer list page uses
            // instead of a bespoke one. Earlier the typeahead's own query
            // (customer_rank filter / image_128 / mobile fields) failed with a
            // generic "Odoo server error" while this proven path kept working.
            final query = pattern.trim();
            return CustomerService.instance.fetchAllCustomers(
              searchQuery: query.isEmpty ? null : query,
              limit: query.isEmpty ? 20 : 100,
            );
          },
          itemBuilder: (context, customer) {
            return ListTile(
              leading: _buildAvatar(customer, isDark),
              title: Text(
                customer.name,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle:
                  customer.email != null &&
                      customer.email!.isNotEmpty &&
                      customer.email!.toLowerCase() != 'false'
                  ? Text(
                      customer.email!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    )
                  : null,
            );
          },
          onSelected: onCustomerSelected,
          loadingBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No customers found',
              style: GoogleFonts.manrope(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          errorBuilder: (context, error) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Could not load customers. Please check your connection and try again.',
              style: GoogleFonts.manrope(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          decorationBuilder: (context, child) => Material(
            type: MaterialType.card,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(Contact customer, bool isDark) {
    if (customer.imageUrl != null &&
        customer.imageUrl!.isNotEmpty &&
        customer.imageUrl != 'false') {
      try {
        final base64String = customer.imageUrl!.contains(',')
            ? customer.imageUrl!.split(',')[1]
            : customer.imageUrl!;
        final bytes = base64Decode(base64String);
        return CircleAvatar(radius: 18, backgroundImage: MemoryImage(bytes));
      } catch (e) {}
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
      child: Text(
        customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
