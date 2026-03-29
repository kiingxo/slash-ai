import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cache_storage_service.dart';

// ── Feature enum ─────────────────────────────────────────────────────────────

enum SlashFeature { prompt, code, project, ops, reviews, settings }

// ── Metadata ─────────────────────────────────────────────────────────────────

class SlashFeatureMeta {
  final SlashFeature feature;
  final String label;
  final String? assetIcon;
  final IconData? icon;
  final String description;

  /// If true the feature is always visible and cannot be disabled.
  final bool required;

  /// If false the feature is not shown in the feature picker (e.g. Settings).
  final bool showInPicker;

  const SlashFeatureMeta({
    required this.feature,
    required this.label,
    this.assetIcon,
    this.icon,
    required this.description,
    this.required = false,
    this.showInPicker = true,
  });
}

const Map<SlashFeature, SlashFeatureMeta> kFeatureMeta = {
  SlashFeature.prompt: SlashFeatureMeta(
    feature: SlashFeature.prompt,
    label: 'Prompt',
    assetIcon: 'assets/slash2.png',
    description:
        'AI chat with full codebase context. Write, review, and explain code inline.',
    required: true,
  ),
  SlashFeature.code: SlashFeatureMeta(
    feature: SlashFeature.code,
    label: 'Code',
    icon: Icons.code,
    description:
        'Syntax-highlighted editor with AI-assisted edits and a built-in file browser.',
  ),
  SlashFeature.project: SlashFeatureMeta(
    feature: SlashFeature.project,
    label: 'Project',
    icon: Icons.insights_rounded,
    description:
        'Repo insights, delivery metrics, and AI-generated executive summaries.',
  ),
  SlashFeature.ops: SlashFeatureMeta(
    feature: SlashFeature.ops,
    label: 'Ops',
    icon: Icons.terminal_rounded,
    description:
        'Connect to your VPS over SSH and monitor CPU, memory, and services.',
  ),
  SlashFeature.reviews: SlashFeatureMeta(
    feature: SlashFeature.reviews,
    label: 'PRs',
    icon: Icons.merge_type,
    description:
        'Review pull requests, triage issues, and track review status across repos.',
  ),
  SlashFeature.settings: SlashFeatureMeta(
    feature: SlashFeature.settings,
    label: 'Settings',
    icon: Icons.settings,
    description:
        'Configure your AI provider, GitHub account, and navigation preferences.',
    required: true,
    showInPicker: false,
  ),
};

// ── Canonical ordering ────────────────────────────────────────────────────────

/// Returns [features] sorted in canonical nav order.
List<SlashFeature> sortedFeatures(Iterable<SlashFeature> features) {
  final order = SlashFeature.values;
  return features.toList()
    ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
}

// ── Preferences notifier ──────────────────────────────────────────────────────

class NavPreferencesNotifier extends StateNotifier<Set<SlashFeature>> {
  static const _enabledKey = 'nav_enabled_features_v2';
  static const _setupDoneKey = 'nav_setup_done';

  NavPreferencesNotifier() : super(_defaultFeatures()) {
    _load();
  }

  static Set<SlashFeature> _defaultFeatures() =>
      SlashFeature.values.toSet();

  void _load() {
    final raw = CacheStorage.fetchString(_enabledKey);
    if (raw != null && raw.isNotEmpty) {
      final ids = raw.split(',').map((e) => e.trim()).toSet();
      final resolved = SlashFeature.values
          .where((f) => ids.contains(f.name))
          .toSet();
      // Always ensure required features are present.
      for (final f in SlashFeature.values) {
        if (kFeatureMeta[f]?.required == true) {
          resolved.add(f);
        }
      }
      if (resolved.isNotEmpty) {
        state = resolved;
      }
    }
  }

  /// Toggle a non-required feature on or off.
  void toggle(SlashFeature feature) {
    if (kFeatureMeta[feature]?.required == true) return;
    final next = Set<SlashFeature>.from(state);
    if (next.contains(feature)) {
      next.remove(feature);
    } else {
      next.add(feature);
    }
    state = next;
    _persist();
  }

  /// Save a complete selection (used by the onboarding feature picker).
  void saveAll(Set<SlashFeature> features) {
    final withRequired = Set<SlashFeature>.from(features);
    for (final f in SlashFeature.values) {
      if (kFeatureMeta[f]?.required == true) {
        withRequired.add(f);
      }
    }
    state = withRequired;
    _persist();
    CacheStorage.save(_setupDoneKey, true);
  }

  void _persist() {
    final ids = state.map((f) => f.name).join(',');
    CacheStorage.save(_enabledKey, ids);
  }

  static bool get isSetupDone =>
      CacheStorage.fetchBool(_setupDoneKey) == true;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final navPreferencesProvider =
    StateNotifierProvider<NavPreferencesNotifier, Set<SlashFeature>>(
      (_) => NavPreferencesNotifier(),
    );

/// Currently visible feature / screen.
final selectedFeatureProvider = StateProvider<SlashFeature>(
  (_) => SlashFeature.prompt,
);

/// Ordered list of features that appear in the bottom nav bar.
/// Required features (prompt, settings) are always included;
/// the rest depend on the user's saved preferences.
final activeNavFeaturesProvider = Provider<List<SlashFeature>>((ref) {
  final prefs = ref.watch(navPreferencesProvider);
  final all = SlashFeature.values.where((f) {
    if (kFeatureMeta[f]?.required == true) return true;
    return prefs.contains(f);
  });
  return sortedFeatures(all);
});
