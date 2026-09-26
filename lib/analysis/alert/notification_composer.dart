import '../../l10n/app_strings.dart';
import 'baby_event_episode.dart';
import 'episode_notification_policy.dart';

class NotificationComposer {
  const NotificationComposer();

  String compose(BabyEventEpisode episode, {AppStrings? strings}) {
    final seconds = (episode.totalCryDurationMs / 1000).round();
    final strongProlongedCry = EpisodeNotificationPolicy.isStrongProlongedCry(
      cryScore: episode.maxCryScore,
      durationMs: episode.totalCryDurationMs,
    );
    final shortResolvedSound = EpisodeNotificationPolicy.isShortResolvedSound(
      resolved: episode.resolved,
      durationMs: episode.totalCryDurationMs,
    );
    final localized = strings;
    if (localized != null) {
      final networkTier = localized.networkQualityLabel(
        episode.streamQualityTier,
      );
      if (strongProlongedCry) {
        return localized.parentEpisodeHighCryAlert(
          seconds: seconds,
          motionAgo: localized.parentMotionAgo(episode.lastMotionAgoMs()),
          networkTier: networkTier,
        );
      }
      if (shortResolvedSound) {
        return localized.parentEpisodeShortSoundAlert(seconds: seconds);
      }
      return localized.parentEpisodeCryAlert(
        seconds: seconds,
        networkTier: networkTier,
      );
    }
    if (strongProlongedCry) {
      final ago = episode.lastMotionAgoMs();
      final motionText =
          ago == null ? 'hareket yok' : '${(ago / 1000).round()} sn önce';
      return 'Yaklaşık $seconds sn süren güçlü ağlama benzeri ses algılandı. Son kamera hareketi $motionText. Yayın ${episode.streamQualityTier.label} modunda.';
    }
    if (shortResolvedSound) {
      return 'Kısa süreli ses yükselmesi algılandı. Devam ederse tekrar bildirilecek.';
    }
    return 'Yaklaşık $seconds sn süren ağlama benzeri sinyal algılandı. Yayın ${episode.streamQualityTier.label} modunda.';
  }
}
