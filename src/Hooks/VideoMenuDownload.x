//
//  VideoMenuDownload.x
//  PrimeFreeBird
//
//  Son entrée de téléchargement, déplacée du menu « … » vers le menu d'appui
//  long de la vidéo, sur TOUTES les vidéos.
//
//  CE QUI EST MESURÉ, et qui rend ce fichier possible (19 août) :
//
//  · Le menu d'appui long vidéo n'est PAS construit par une méthode
//    Objective-C. Sa fonction vit dans un trou de la table des IMP de
//    T1Twitter (entre 0x2f7df8 et 0x314818) : rien à accrocher là.
//    Le seul point ObjC du chemin est `+[UIMenu menuWithTitle:children:]`
//    (2 arguments) — le menu « … », lui, passe par la variante à 5.
//
//  · L'entrée native « Download Video » est gardée dans T1Twitter par
//    `cbz` sur `[[média entityURL] networkURL]` (0x30d530). URL nulle ⇒ tout
//    le bloc de téléchargement est sauté : ni « Download Video », ni
//    « Download ». C'est la cause de l'intermittence, pas le Premium ni
//    `allowDownload` (les deux mesurés hors circuit).
//
//  · 0,4 s AVANT l'assemblage du menu, Twitter construit un
//    `UIActivityViewController` dont l'unique activityItem est un
//    `T1ActivityItemProvider` — objet qui expose `-status`. C'est de là que
//    vient le contexte : sans lui, une entrée ajoutée au menu téléchargerait
//    la vidéo d'un AUTRE tweet.
//
//  Aucune supposition sur du texte anglais dans la DÉCISION : l'ajout est
//  conditionné au statut fraîchement capturé et à son média vidéo/GIF
//  (mediaType 2 ou 3, exactement le test de MediaDownloads.x). Les titres ne
//  servent qu'à éviter un doublon quand l'entrée native est déjà là.
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// T1ActivityItemProvider n'est PAS déclaré dans src/Headers : une coquille de
// déclaration sert de cast. Jamais instanciée, jamais messagée comme classe —
// donc aucun symbole de classe n'est référencé, aucune erreur de lien.
@interface NFBVMDProviderShim : NSObject
- (id)status;
@end

// Fenêtre de fraîcheur entre la feuille de partage et le menu. Mesuré : 0,4 s.
// Au-delà, on n'ajoute rien — mieux vaut pas d'entrée qu'une mauvaise vidéo.
static const NSTimeInterval kNFBVMDFreshness = 3.0;

static id                    gNFBVMDStatus;        // le tweet sous le doigt
static NSTimeInterval        gNFBVMDStatusTime;
static DownloadInlineButton* gNFBVMDDownloader;    // son téléchargeur, réutilisé

// MARK: - Contexte : la feuille de partage précède le menu

%hook UIActivityViewController

- (id)initWithActivityItems:(NSArray*)activityItems
      applicationActivities:(NSArray*)applicationActivities {
    id result = %orig;
    @try {
        for (id item in activityItems) {
            if (![item respondsToSelector:@selector(status)]) {
                continue;
            }
            id status = [(NFBVMDProviderShim*)item status];
            if (!status) {
                continue;
            }
            gNFBVMDStatus = status;
            gNFBVMDStatusTime = [NSDate timeIntervalSinceReferenceDate];
            break;
        }
    } @catch (id exception) {
    }
    return result;
}

%end

// MARK: - Le média du tweet capturé

// Reprend TEL QUEL le test de MediaDownloads.x : mediaType 2 = GIF, 3 = vidéo.
static NSArray* NFBVMDFreshVideoEntities(void) {
    if (!gNFBVMDStatus) {
        return nil;
    }
    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - gNFBVMDStatusTime;
    if (age < 0 || age > kNFBVMDFreshness) {
        return nil;
    }
    if (![gNFBVMDStatus respondsToSelector:@selector(entities)]) {
        return nil;
    }
    NSArray* mediaEntities = [[gNFBVMDStatus entities] media];
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            return mediaEntities;
        }
    }
    return nil;
}

// Une entrée de téléchargement est-elle déjà là ? Sert UNIQUEMENT à ne pas
// doubler l'entrée native quand elle apparaît (vidéo avec networkURL) — et,
// au passage, à ne pas ajouter la nôtre deux fois si le menu est reconstruit.
static BOOL NFBVMDAlreadyHasDownload(NSArray* children) {
    for (id element in children) {
        if (![element respondsToSelector:@selector(title)]) {
            continue;
        }
        NSString* title = [element title];
        if (title.length == 0) {
            continue;
        }
        if ([[title lowercaseString] rangeOfString:@"download"].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static UIImage* NFBVMDGlyph(void) {
    UIImage* glyph = nil;
    if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        glyph = [UIImage tfn_vectorImageNamed:@"arrow_down_circle_stroke"
                                     fitsSize:CGSizeMake(24.0, 24.0)
                                    fillColor:[UIColor labelColor]];
    }
    if (!glyph) {
        glyph = [UIImage systemImageNamed:@"arrow.down.circle"];
    }
    return glyph;
}

// Rend le tableau d'enfants à poser : inchangé, ou avec notre entrée insérée
// AVANT le dernier item (« Share via… »), comme il le fait déjà dans
// MediaDownloads.x pour le menu « … ».
static NSArray* NFBVMDAugmentedChildren(NSArray* children) {
    if (children.count == 0) {
        return children;
    }
    if (![BHTSettings boolForKey:@"download_videos"]) {
        return children;
    }
    if (NFBVMDAlreadyHasDownload(children)) {
        return children;
    }
    NSArray* mediaEntities = NFBVMDFreshVideoEntities();
    if (mediaEntities.count == 0) {
        return children;
    }

    if (!gNFBVMDDownloader) {
        gNFBVMDDownloader = [%c(DownloadInlineButton) new];
    }
    DownloadInlineButton* downloader = gNFBVMDDownloader;

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"];
    if (title.length == 0) {
        return children;
    }

    UIAction* action = [UIAction actionWithTitle:title
                                           image:NFBVMDGlyph()
                                      identifier:nil
                                         handler:^(UIAction* sender) {
        [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
    }];
    if (!action) {
        return children;
    }

    NSMutableArray* augmented = [children mutableCopy];
    [augmented insertObject:action atIndex:augmented.count - 1];
    NFBDebugLog(@"[dlvideo] entrée ajoutée au menu vidéo (%lu → %lu items)",
                (unsigned long)children.count, (unsigned long)augmented.count);
    return augmented;
}

// MARK: - Le menu d'appui long vidéo (fabrique à 2 arguments)

%hook UIMenu

+ (id)menuWithTitle:(NSString*)title children:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        finalChildren = NFBVMDAugmentedChildren(children);
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(title, finalChildren);
}

%end

%ctor {
    NFBDebugLog(@"[dlvideo] téléchargement vidéo dans le menu d'appui long — armé");
}
