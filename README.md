# PDF Facile

Application mobile Flutter (Android et iOS) pour modifier facilement des PDF, **100 % hors ligne** :
aucune connexion n'est nécessaire, aucun fichier ne quitte le téléphone (sauf si vous le partagez).

## Fonctions

| Catégorie | Ce que vous pouvez faire |
|---|---|
| **Annoter** | stylo à main levée, surligneur, texte (accents, €), rectangle, cercle, ligne, flèche, gomme ; couleur et épaisseur au choix ; sélection, déplacement, redimensionnement, duplication |
| **Signature et images** | dessiner une signature au doigt (mémorisée pour la suite), insérer une photo (galerie ou appareil photo) |
| **Pages** | réorganiser par glisser-déposer, pivoter, dupliquer, supprimer, ajouter des pages blanches, fusionner avec un autre PDF |
| **Formulaires** | remplir les champs texte, cases à cocher, boutons radio et listes ; option « figer » le formulaire |
| **Export Word** | conversion en .docx : « texte modifiable » (paragraphes, tailles, retraits) ou « mise en page identique » (pages en images, idéal pour les scans) |
| **Documents** | ouvrir un PDF (y compris protégé par mot de passe), créer un PDF vierge, créer un PDF à partir de photos, renommer, partager, enregistrer une copie |

Annuler et rétablir couvrent toutes les actions. Pour zoomer, pincez à deux doigts (avec n'importe quel outil).
En mode « Naviguer », balayez horizontalement pour changer de page.

## Structure

```
lib/
  main.dart                     point d'entrée, thème, localisation FR
  models/annotation.dart        modèle d'annotation (coordonnées normalisées)
  services/
    pdf_service.dart            écriture des annotations, formulaires, création (Syncfusion PDF)
    page_service.dart           réorganisation / rotation / fusion de pages (PDFium via pdfrx)
    pdf_import.dart             ouverture et déverrouillage des PDF protégés
    document_store.dart         bibliothèque locale des PDF et des signatures
  screens/                      accueil, éditeur, pages, formulaire, signature
  widgets/                      rendu des pages, dessin des annotations, dialogues
assets/fonts/Roboto-Regular.ttf police Unicode intégrée au PDF pour le texte ajouté
```

Les annotations restent modifiables tant que vous n'enregistrez pas. Elles sont écrites dans
le contenu du PDF au moment de l'enregistrement, du partage ou d'une opération sur les pages
ou le formulaire.

## Installer sans câble (Release GitHub)

Chaque tag de version déclenche une compilation sur GitHub ([workflow](.github/workflows/release-apk.yml)) :

```bash
git tag v1.0.1
git push origin v1.0.1
```

Quelques minutes plus tard, l'APK signé apparaît sur la page **Releases** du dépôt. Sur le téléphone,
ouvrez cette page, téléchargez l'APK et installez-le. Les mises à jour s'installent par-dessus.

À partir de la version 1.0.2, l'app vérifie au démarrage (si Internet est disponible) la dernière
release du dépôt et propose la mise à jour : téléchargement dans l'app puis confirmation dans
l'installeur Android. Vérification manuelle : menu ⋮ > « Rechercher une mise à jour ». Le dépôt
doit rester public.

Prérequis : les secrets `ANDROID_KEYSTORE_BASE64` et `ANDROID_KEYSTORE_PASSWORD` dans
*Settings > Secrets and variables > Actions*. La clé de signature est conservée hors du dépôt
(`C:\claude\appli-pdf-signature`) ; le build local la lit via `android/key.properties` (ignoré par git).

## Compiler

Outils installés sur ce PC : Flutter dans `C:\src\flutter`, SDK Android dans `C:\src\android-sdk`.

```bash
C:\src\flutter\bin\flutter build apk --release
```

L'APK est produit dans `build/app/outputs/flutter-apk/app-release.apk`. Copiez-le sur le téléphone
et ouvrez-le (autorisez « installer des applications inconnues »), ou branchez le téléphone en USB
avec le débogage activé :

```bash
C:\src\flutter\bin\flutter install
```

**iOS** : la compilation nécessite un Mac avec Xcode (`flutter build ios`).


## Licences

- `syncfusion_flutter_pdf` : licence commerciale Syncfusion, gratuite via la *Community License*
  (particuliers et entreprises de moins de 1 M$ de chiffre d'affaires).
- `pdfrx` / PDFium : licences MIT / BSD. Police Roboto : Apache 2.0.
