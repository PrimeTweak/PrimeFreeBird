//
//  RefreshSounds.x
//  PrimeFreeBird
//
//  Restaure le son "pull-to-refresh" classique de Twitter.
//
//  Contexte (pour qui reprend ce code) : sur Twitter 12.9 / iOS 26, le
//  pull-to-refresh du fil est passe en SwiftUI. L'ancien hook
//  -[TFNPullToRefreshControl _setStatus:fromScrolling:] a disparu (methode
//  retiree du binaire), et ni le setter -setDidRequestPullToRefresh: ni le
//  lecteur de son central -[UIApplication _t1_playSoundNamed:] ne sont plus
//  sur le chemin du geste (verifie : 0 declenchement). De plus, les fichiers
//  son natifs de Twitter ont ete retires de l'app, donc il n'y a plus rien a
//  reactiver cote Twitter.
//
//  Approche retenue : le pull-to-refresh reste un GESTE DE SCROLL. On detecte
//  le tirage via le scroll delegate ObjC (toujours present), sur le controleur
//  de liste TFNItemsDataViewController. Quand l'utilisateur relache apres avoir
//  tire la liste au-dela d'un seuil, on joue notre son.
//
//  Le son est fourni par le tweak en PCM (psst2.caf). IMPORTANT : le format
//  doit etre PCM (CAF/WAV/AIFF) -- AudioServicesCreateSystemSoundID NE decode
//  PAS l'AAC (un .aac se cree sans erreur mais reste muet).
//
//  Reglable par l'utilisateur via le toggle "restore_refresh_sounds"
//  (page Timelines, active par defaut).

#import "HookHelpers.h"

// Seuil de tirage (points sous la position de repos) au-dela duquel on
// considere que c'est un vrai pull-to-refresh et non un scroll ordinaire.
// Au repos, le haut du fil peut deja etre legerement negatif (encart de la
// barre de navigation) ; -100 laisse une marge nette. Un vrai tirage descend
// bien plus bas (mesure ~ -375), donc le son se declenche de facon fiable
// sans jamais sonner sur un scroll normal.
static const CGFloat kNFBPullToRefreshThreshold = -100.0;

static void NFBPlayRefreshSound(void) {
    static SystemSoundID sound = 0;
    static BOOL triedToLoad = NO;

    if (!triedToLoad) {
        triedToLoad = YES;
        NSURL* url = [[BHTBundle sharedBundle] pathForFile:@"psst2.caf"];
        if (url) {
            if (AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &sound) !=
                kAudioServicesNoError) {
                sound = 0;
            }
        }
    }
    if (sound) {
        AudioServicesPlaySystemSound(sound);
    }
}

%hook TFNItemsDataViewController

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
    %orig;

    if (![BHTSettings boolForKey:@"restore_refresh_sounds"]) {
        return;
    }

    // contentOffset.y au moment ou le doigt se leve : tres negatif = la liste a
    // ete tiree vers le bas au-dela du sommet = intention de rafraichir.
    if (scrollView.contentOffset.y < kNFBPullToRefreshThreshold) {
        NFBPlayRefreshSound();
    }
}

%end

%ctor {
    // AudioToolbox n'est pas lie au tweak : on lie ses symboles paresseusement
    // avant tout appel a AudioServices.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);
    %init;
}
