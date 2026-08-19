// ---------------------------------------------------------------------------
//  VideoDownloadProbe.x — SONDE DE MENUS, v2. LECTURE SEULE.
//
//  Remplace en entier la sonde precedente, qui n'accrochait que
//  T1Activity -canPerformWithActivityItems: et n'a jamais produit une ligne.
//
//  Ce qui est MESURE avant d'ecrire ceci (3 videos, 3 lectures identiques) :
//    - le menu « ... » passe par _t1_actionItemsForStatus: (MediaDownloads.x)
//      et ne contient JAMAIS l'entree native « Download Video » ;
//    - sur 4 min 30 de journal continu, aucun autre geste n'a atteint la sonde.
//  => on se place ici sur les points de passage OBLIGES d'UIKit, et non sur
//     des classes Twitter supposees.
//
//  AUCUN hook ne change de comportement : chaque %orig est renvoye tel quel,
//  aucune valeur n'est reecrite, aucune vue n'est touchee.
// ---------------------------------------------------------------------------

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <string.h>

// Journal du debogueur maison.
// Declare en weak_import : si le symbole n'existe pas, il vaut NULL et on
// retombe sur NSLog. Aucun en-tete a importer, donc aucun risque de casser
// le build sur un chemin d'include que je n'ai pas sous la main.
extern void NFBDebugLog(NSString *format, ...) __attribute__((weak_import));

// Typedef pour le bloc du handler : evite des parentheses imbriquees dans une
// signature de hook, que le parseur de Logos digere mal.
typedef void (^NFBProbeActionHandler)(UIAction *action);

// Coquille de declaration pour parler a T1Activity sans en-tete.
// Jamais instanciee, jamais referencee comme classe : sert uniquement de cast.
@interface NFBProbeActivityShim : NSObject
- (NSString *)identifier;
- (NSString *)actionTitle;
- (NSString *)mediaKey;
- (NSString *)mediaType;
@end

// ---------------------------------------------------------------------------
//  Journal
// ---------------------------------------------------------------------------

static void NFBProbeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (line.length == 0) {
        return;
    }
    if (NFBDebugLog != NULL) {
        NFBDebugLog(@"%@", line);
    } else {
        NSLog(@"%@", line);
    }
}

// ---------------------------------------------------------------------------
//  Deduplication a fenetre glissante
//
//  Sans elle, un seul geste noie les 12 dernieres decisions du debogueur.
//  La fenetre se vide apres 4 s d'inactivite : chaque nouveau geste repart
//  donc de zero et reimprime ses lignes.
// ---------------------------------------------------------------------------

static NSMutableSet *gNFBProbeSeen = nil;
static NSTimeInterval gNFBProbeLastSeenTime = 0;

static NSLock *NFBProbeLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

static BOOL NFBProbeFirstTime(NSString *key) {
    if (key.length == 0) {
        return NO;
    }
    BOOL first = NO;
    NSLock *lock = NFBProbeLock();
    [lock lock];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gNFBProbeSeen == nil) {
        gNFBProbeSeen = [[NSMutableSet alloc] init];
    }
    if (now - gNFBProbeLastSeenTime > 4.0) {
        [gNFBProbeSeen removeAllObjects];
    }
    gNFBProbeLastSeenTime = now;
    if (![gNFBProbeSeen containsObject:key]) {
        [gNFBProbeSeen addObject:key];
        first = YES;
    }
    if (gNFBProbeSeen.count > 300) {
        [gNFBProbeSeen removeAllObjects];
    }
    [lock unlock];
    return first;
}

// ---------------------------------------------------------------------------
//  Lecture des elements de menu
// ---------------------------------------------------------------------------

static NSString *NFBProbeTitleOf(id element) {
    NSString *title = nil;
    if ([element respondsToSelector:@selector(title)]) {
        title = [element title];
    }
    if (title.length > 0) {
        return title;
    }
    return [NSString stringWithFormat:@"(sans titre:%@)", NSStringFromClass([element class])];
}

static NSString *NFBProbeTitlesOf(NSArray *children) {
    if (children.count == 0) {
        return @"(aucun enfant)";
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (id element in children) {
        NSString *title = NFBProbeTitleOf(element);
        if ([element isKindOfClass:[UIMenu class]]) {
            NSArray *nested = [(UIMenu *)element children];
            NSString *nestedTitles = @"";
            if (nested.count > 0) {
                NSMutableArray *inner = [NSMutableArray array];
                for (id sub in nested) {
                    [inner addObject:NFBProbeTitleOf(sub)];
                }
                nestedTitles = [inner componentsJoinedByString:@" / "];
            }
            [parts addObject:[NSString stringWithFormat:@"[sous-menu: %@]", nestedTitles]];
        } else {
            [parts addObject:title];
        }
    }
    return [parts componentsJoinedByString:@" | "];
}

// Un titre est-il un candidat « telechargement » ?
static BOOL NFBProbeLooksLikeDownload(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    NSString *lower = [text lowercaseString];
    if ([lower rangeOfString:@"download"].location != NSNotFound) {
        return YES;
    }
    if ([lower rangeOfString:@"save"].location != NSNotFound) {
        return YES;
    }
    return NO;
}

static void NFBProbeReportMenu(NSString *porte, NSString *title, NSString *identifier, NSArray *children) {
    if (children.count < 2) {
        return;
    }
    NSString *titles = NFBProbeTitlesOf(children);
    // La cle volontairement SANS la porte : si deux fabriques s'appellent en
    // cascade pour le meme menu, une seule ligne sort.
    if (!NFBProbeFirstTime([NSString stringWithFormat:@"menu|%@", titles])) {
        return;
    }
    NSString *nom = (title.length > 0) ? title : @"(sans titre)";
    NSString *ident = (identifier.length > 0) ? identifier : @"-";
    NFBProbeLog(@"[sonde] UIMenu %@ « %@ » id=%@ · %lu item(s) · %@",
                porte, nom, ident, (unsigned long)children.count, titles);
}

// ---------------------------------------------------------------------------
//  Adresse de l'appelant
//
//  Avec les stubs `_objc_msgSend$sel` (bl vers le stub, puis br vers
//  objc_msgSend, puis br vers l'IMP : aucune nouvelle trame de pile),
//  __builtin_return_address(0) dans le hook rend l'adresse du VRAI appelant.
//  __TEXT ayant un vmaddr de 0 dans ces binaires, l'offset rendu ici est
//  directement l'adresse a chercher dans l'IPA.
// ---------------------------------------------------------------------------

static NSString *NFBProbeCallerDescription(void *returnAddress) {
    if (returnAddress == NULL) {
        return @"(inconnu)";
    }
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr(returnAddress, &info) == 0 || info.dli_fbase == NULL) {
        return [NSString stringWithFormat:@"(hors image) %p", returnAddress];
    }
    const char *chemin = (info.dli_fname != NULL) ? info.dli_fname : "?";
    const char *fin = strrchr(chemin, '/');
    NSString *image = [NSString stringWithUTF8String:((fin != NULL) ? (fin + 1) : chemin)];
    unsigned long long offset =
        (unsigned long long)((uintptr_t)returnAddress - (uintptr_t)info.dli_fbase);
    NSString *symbole = @"";
    if (info.dli_sname != NULL) {
        symbole = [NSString stringWithFormat:@" ~%s", info.dli_sname];
    }
    return [NSString stringWithFormat:@"%@+0x%llx%@", image, offset, symbole];
}

// Titres du menu video, releves dans son journal du 19 aout.
// « Tweet Video » sort dans les DEUX cas (avec et sans Download Video) :
// c'est lui qui garantit qu'on obtiendra l'adresse du constructeur.
static BOOL NFBProbeIsVideoMenuTitle(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    static NSArray *titres = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titres = @[@"Tweet Video", @"Copy Video Link", @"React with Video",
                   @"Download Video", @"Add to Offline"];
    });
    return [titres containsObject:text];
}

// Rapport commun aux deux variantes de T1ShareController.
static void NFBProbeReportShareItems(NSString *porte, id result, NSString *extra) {
    NSArray *items = nil;
    if ([result isKindOfClass:[NSArray class]]) {
        items = (NSArray *)result;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (id item in items) {
        NSString *label = nil;
        NFBProbeActivityShim *shim = (NFBProbeActivityShim *)item;
        if ([item respondsToSelector:@selector(title)]) {
            label = [item title];
        }
        if (label.length == 0 && [item respondsToSelector:@selector(actionTitle)]) {
            label = [shim actionTitle];
        }
        if (label.length == 0) {
            label = [NSString stringWithFormat:@"(%@)", NSStringFromClass([item class])];
        }
        [parts addObject:label];
    }
    NSString *liste = (parts.count > 0) ? [parts componentsJoinedByString:@" | "] : @"(vide)";
    if (NFBProbeFirstTime([NSString stringWithFormat:@"share|%@|%@|%@", porte, liste, extra])) {
        NFBProbeLog(@"[sonde] %@ · %lu item(s) · %@ · %@",
                    porte, (unsigned long)parts.count, extra, liste);
    }
}

// ---------------------------------------------------------------------------
//  UIMenu — les trois fabriques publiques
// ---------------------------------------------------------------------------

%hook UIMenu

+ (id)menuWithTitle:(NSString *)title
              image:(UIImage *)image
         identifier:(NSString *)identifier
            options:(NSUInteger)options
           children:(NSArray *)children {
    id result = %orig;
    NFBProbeReportMenu(@"5args", title, identifier, children);
    return result;
}

+ (id)menuWithTitle:(NSString *)title children:(NSArray *)children {
    id result = %orig;
    NFBProbeReportMenu(@"2args", title, nil, children);
    return result;
}

+ (id)menuWithChildren:(NSArray *)children {
    id result = %orig;
    NFBProbeReportMenu(@"1arg", nil, nil, children);
    return result;
}

%end

// ---------------------------------------------------------------------------
//  UIAction — la seule fabrique publique.
//  Filtree sur « download » / « save » pour ne pas noyer le journal : toute
//  action de telechargement de l'app passe forcement ici, quel que soit le
//  menu qui l'accueille ensuite.
// ---------------------------------------------------------------------------

%hook UIAction

+ (id)actionWithTitle:(NSString *)title
                image:(UIImage *)image
           identifier:(NSString *)identifier
              handler:(NFBProbeActionHandler)handler {
    void *retour = __builtin_return_address(0);
    id result = %orig;
    BOOL candidat = NFBProbeLooksLikeDownload(title)
                 || NFBProbeLooksLikeDownload(identifier)
                 || NFBProbeIsVideoMenuTitle(title);
    if (candidat) {
        NSString *nom = (title.length > 0) ? title : @"(sans titre)";
        NSString *ident = (identifier.length > 0) ? identifier : @"-";
        NSString *appelant = NFBProbeCallerDescription(retour);
        if (NFBProbeFirstTime([NSString stringWithFormat:@"action|%@|%@|%@", nom, ident, appelant])) {
            NFBProbeLog(@"[sonde] UIAction « %@ » id=%@ · appelant %@", nom, ident, appelant);
        }
    }
    return result;
}

%end

// ---------------------------------------------------------------------------
//  Feuille de partage — la piste designee par le nom de la cle native
//  DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL (« activity view » = feuille de partage).
// ---------------------------------------------------------------------------

%hook UIActivityViewController

- (id)initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray *)applicationActivities {
    id result = %orig;
    NSMutableArray *noms = [NSMutableArray array];
    for (id activity in applicationActivities) {
        NSString *ident = nil;
        NFBProbeActivityShim *shim = (NFBProbeActivityShim *)activity;
        if ([activity respondsToSelector:@selector(identifier)]) {
            ident = [shim identifier];
        }
        if (ident.length > 0) {
            [noms addObject:ident];
        } else {
            [noms addObject:NSStringFromClass([activity class])];
        }
    }
    NSString *liste = (noms.count > 0) ? [noms componentsJoinedByString:@" | "] : @"(aucune)";
    if (NFBProbeFirstTime([NSString stringWithFormat:@"sheet|%@", liste])) {
        NFBProbeLog(@"[sonde] feuille de partage · %lu activite(s) · %@",
                    (unsigned long)applicationActivities.count, liste);
    }
    return result;
}

%end

// ---------------------------------------------------------------------------
//  T1Activity — conserve de la sonde precedente.
//  RESERVE DITE FRANCHEMENT : ce hook ne voit que l'implementation de la
//  classe de BASE. Si l'activite « DownloadVideo » est une sous-classe qui
//  redefinit ces methodes, elle passe a cote — ce qui expliquerait a soi seul
//  le silence de la sonde v1.
// ---------------------------------------------------------------------------

%hook T1Activity

- (BOOL)isSupported {
    BOOL supported = %orig;
    NFBProbeActivityShim *shim = (NFBProbeActivityShim *)self;
    NSString *ident = nil;
    if ([shim respondsToSelector:@selector(identifier)]) {
        ident = [shim identifier];
    }
    if (ident.length == 0) {
        ident = NSStringFromClass([shim class]);
    }
    if (NFBProbeFirstTime([NSString stringWithFormat:@"act|%@|%d", ident, (int)supported])) {
        NFBProbeLog(@"[sonde] T1Activity isSupported=%@ · %@",
                    supported ? @"OUI" : @"NON", ident);
    }
    return supported;
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
    BOOL can = %orig;
    NFBProbeActivityShim *shim = (NFBProbeActivityShim *)self;
    NSString *ident = nil;
    if ([shim respondsToSelector:@selector(identifier)]) {
        ident = [shim identifier];
    }
    if (ident.length == 0) {
        ident = NSStringFromClass([shim class]);
    }
    if (NFBProbeFirstTime([NSString stringWithFormat:@"can|%@|%d", ident, (int)can])) {
        NFBProbeLog(@"[sonde] T1Activity canPerform=%@ · %@ · %lu item(s)",
                    can ? @"OUI" : @"NON", ident, (unsigned long)activityItems.count);
    }
    return can;
}

%end

// ---------------------------------------------------------------------------
//  T1ShareController — LE CONSTRUCTEUR DU MENU, nomme dans l'IPA 12.15.
//
//  Encodage de types releve dans __objc_methtype :
//      @80@0:8@16@24@32@40@48@56@64@72
//  => les 8 arguments sont TOUS des objets, aucun struct passe par valeur.
//     C'est ce qui rend ce hook sur une classe Swift sans danger.
//
//  On journalise le tableau RETOURNE : c'est lui qui contient, ou non,
//  l'item « Download Video ».
// ---------------------------------------------------------------------------

%hook _TtC14T1TwitterSwift17T1ShareController

// Encodage releve dans __objc_methtype : @80@0:8@16@24@32@40@48@56@64@72
// => 8 arguments, tous des objets, aucun struct par valeur.
- (id)menuSheetActionItemsForShareable:(id)shareable
                               account:(id)account
                         layoutMetrics:(id)layoutMetrics
                        viewController:(id)viewController
                         popoverSource:(id)popoverSource
                         scribeContext:(id)scribeContext
                           persistence:(id)persistence
                         videoShareURL:(id)videoShareURL {
    id result = %orig;
    NSString *avecURL = (videoShareURL != nil) ? @"videoShareURL=oui" : @"videoShareURL=non";
    NFBProbeReportShareItems(@"menuSheetActionItems", result, avecURL);
    return result;
}

// Encodage releve dans __objc_methtype : @72@0:8@16@24@32@40@48@56@64
// => 7 arguments, tous des objets.
- (id)actionItemsForShareable:(id)shareable
                      account:(id)account
                layoutMetrics:(id)layoutMetrics
               viewController:(id)viewController
                popoverSource:(id)popoverSource
                scribeContext:(id)scribeContext
                  persistence:(id)persistence {
    id result = %orig;
    NFBProbeReportShareItems(@"actionItems", result, @"7 args");
    return result;
}

%end

// ---------------------------------------------------------------------------
//  TFSTwitterEntityMedia -allowDownload — LE DRAPEAU CANDIDAT.
//
//  Mesure dans l'IPA : simple `ldrb` sur un ivar => BOOL stocke, choisi par
//  l'AUTEUR du tweet (ApiMediaEntityFragment.AllowDownloadStatus cote serveur).
//
//  RESERVE : ses deux seuls appels ObjC dans T1Twitter sont sur le chemin de
//  COMPOSITION, pas sur celui du menu. Si AUCUNE ligne ne sort ici pendant
//  l'ouverture du menu, c'est que le lecteur est du Swift en acces direct au
//  champ — et ce silence est alors la mesure decisive, pas un echec.
// ---------------------------------------------------------------------------

%hook TFSTwitterEntityMedia

- (BOOL)allowDownload {
    BOOL allowed = %orig;
    NFBProbeActivityShim *shim = (NFBProbeActivityShim *)self;
    NSString *key = nil;
    if ([shim respondsToSelector:@selector(mediaKey)]) {
        key = [shim mediaKey];
    }
    if (key.length == 0) {
        key = @"(sans mediaKey)";
    }
    NSString *type = nil;
    if ([shim respondsToSelector:@selector(mediaType)]) {
        type = [shim mediaType];
    }
    NSString *typeTexte = (type.length > 0) ? type : @"?";
    if (NFBProbeFirstTime([NSString stringWithFormat:@"media|%@|%d", key, (int)allowed])) {
        NFBProbeLog(@"[sonde] allowDownload=%@ · type=%@ · %@",
                    allowed ? @"OUI" : @"NON", typeTexte, key);
    }
    return allowed;
}

%end

// ---------------------------------------------------------------------------
//  Marqueur de version : prouve que CE binaire-ci est bien celui qui tourne.
// ---------------------------------------------------------------------------

%ctor {
    NFBProbeLog(@"[sonde] sonde de menus v4 armee (adresse de l'appelant + actionItems 7 args)");
}
