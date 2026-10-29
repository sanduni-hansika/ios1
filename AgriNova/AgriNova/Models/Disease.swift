import Foundation
import SwiftUI

enum Pathogen: String, CaseIterable, Hashable {
    case fungus, bacteria, virus, pest, none
    var titleKey: String { "pathogen.\(rawValue)" }
    var icon: String {
        switch self { case .fungus: "aqi.medium"; case .bacteria: "circle.hexagongrid.fill"; case .virus: "waveform.path.ecg"
        case .pest: "ant.fill"; case .none: "checkmark.seal.fill" }
    }
    var color: Color {
        switch self { case .fungus: Theme.violet; case .bacteria: Theme.sun; case .virus: Theme.danger; case .pest: Theme.sky; case .none: Theme.leaf }
    }
}

/// One class the on-device model can output (PlantVillage tomato classes).
struct Disease: Identifiable, Hashable {
    let id: String                 // exact Core ML class label, e.g. "Tomato___Early_blight"
    let key: String                // asset / file key, e.g. "early_blight"
    let name: [String]             // en, si, ta
    let scientific: String
    let pathogen: Pathogen
    let severity: Int              // 0 (none) ... 3 (severe)
    let summary: [String]          // en, si, ta
    let symptoms: [String]
    let conditions: String
    let spread: String
    let organic: [String]
    let chemical: [String]
    let cultural: [String]
    let prevention: [String]

    var isHealthy: Bool { pathogen == .none }
    var imageName: String { "disease_\(key)" }
    var displayName: String { name.localized }
    var displaySummary: String { summary.localized }
    /// Diseases whose spread is driven by humid, wet weather – used for early-warning logic.
    var isMoistureDriven: Bool { [.fungus, .bacteria].contains(pathogen) }

    func sampleImage(_ n: Int) -> UIImage? {
        guard let path = Bundle.main.path(forResource: "sample_\(key)_\(n)", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

enum Species {
    static let tomatoName = ["Tomato", "තක්කාලි", "தக்காளி"]
    static let tomatoIntro = [
        "Tomato (Solanum lycopersicum) is one of Sri Lanka's most important vegetable crops. It grows best in warm, well-drained soil with steady moisture, and is sensitive to leaf diseases in humid weather.",
        "තක්කාලි (Solanum lycopersicum) ශ්‍රී ලංකාවේ වැදගත්ම එළවළු බෝගයකි. උණුසුම්, හොඳින් ජලය බැස යන පසක් සහ ස්ථාවර තෙතමනයක් එයට සුදුසු වන අතර ආර්ද්‍ර කාලගුණයේදී කොළ රෝගවලට ඉතා සංවේදී වේ.",
        "தக்காளி (Solanum lycopersicum) இலங்கையின் முக்கிய காய்கறிப் பயிர்களில் ஒன்று. சூடான, நீர் வடியும் மண்ணில் நன்றாக வளரும்; ஈரப்பதமான காலநிலையில் இலை நோய்களுக்கு எளிதில் ஆளாகும்."
    ]
    static func name(for label: String) -> String { tomatoName.localized }
    static func intro(for label: String) -> String { tomatoIntro.localized }
}

enum DiseaseCatalog {
    static let all: [Disease] = [
        Disease(
            id: "Tomato___Early_blight", key: "early_blight",
            name: ["Early Blight", "මුල් අංගමාරය", "ஆரம்ப இலை கருகல்"],
            scientific: "Alternaria solani", pathogen: .fungus, severity: 2,
            summary: ["A common fungal disease that makes dark, ringed spots on older leaves first.",
                      "පැරණි කොළවල ප්‍රථමයෙන් වළලු සහිත තද පැහැති ලප ඇති කරන පොදු දිලීර රෝගයකි.",
                      "முதலில் பழைய இலைகளில் வளையங்களுடன் கூடிய கருப்பு புள்ளிகளை உண்டாக்கும் பொதுவான பூஞ்சை நோய்."],
            symptoms: ["Brown spots with concentric 'bullseye' rings on lower leaves", "Yellow halo around each spot", "Leaves yellow, wither and drop from the bottom up", "Dark sunken lesions on stems and fruit shoulders"],
            conditions: "Warm days (24–29 °C), frequent dew or rain, and stressed or nutrient-poor plants.",
            spread: "Spores survive in crop debris and soil, then splash or blow onto leaves.",
            organic: ["Remove and burn the lowest infected leaves", "Spray neem oil (0.5%) or a copper-soap fungicide every 7 days", "Apply compost tea or Trichoderma-based bio-fungicide to the root zone"],
            chemical: ["Use a protectant fungicide such as mancozeb or chlorothalonil as labelled", "Rotate with a systemic option (e.g. azoxystrobin) to avoid resistance", "Follow label dose and pre-harvest interval; ask your extension officer"],
            cultural: ["Mulch to stop soil splash", "Stake plants and prune lower leaves for airflow", "Water at the base in the morning", "Rotate away from tomato/potato for 2–3 seasons"],
            prevention: ["Use disease-free seedlings", "Keep plants well fed (potassium, calcium)", "Clear crop debris after harvest"]),
        Disease(
            id: "Tomato___Late_blight", key: "late_blight",
            name: ["Late Blight", "පසු අංගමාරය", "பிந்திய இலை கருகல்"],
            scientific: "Phytophthora infestans", pathogen: .fungus, severity: 3,
            summary: ["A fast, destructive disease in cool, wet weather that can destroy a crop in days.",
                      "සිසිල්, තෙත් කාලගුණයේදී දින කිහිපයකින් බෝගය විනාශ කළ හැකි වේගවත් රෝගයකි.",
                      "குளிர்ந்த ஈரமான வானிலையில் சில நாட்களில் பயிரை அழிக்கக்கூடிய வேகமான நோய்."],
            symptoms: ["Large, greasy, water-soaked grey-green patches", "White fuzzy growth under leaves in humid mornings", "Brown firm rot on fruit", "Stems turn dark and plants collapse quickly"],
            conditions: "Cool nights (10–20 °C), long leaf wetness, high humidity above 90%, misty hill-country weather.",
            spread: "Wind-borne spores travel between fields within hours.",
            organic: ["Remove and bag infected plants immediately – do not compost", "Copper-based organic spray as a preventive on healthy plants nearby", "Improve airflow by wider spacing"],
            chemical: ["Protectant (mancozeb / chlorothalonil) on neighbours", "Systemic products such as metalaxyl-based or cymoxanil mixes as labelled", "Alternate modes of action every spray"],
            cultural: ["Avoid overhead irrigation", "Use raised beds and drainage", "Do not plant near potato", "Scout twice weekly during misty weather"],
            prevention: ["Plant resistant varieties where available", "Monitor local outbreak map and weather risk", "Clean tools between plots"]),
        Disease(
            id: "Tomato___Bacterial_spot", key: "bacterial_spot",
            name: ["Bacterial Spot", "බැක්ටීරියා ලප රෝගය", "பாக்டீரியா புள்ளி நோய்"],
            scientific: "Xanthomonas spp.", pathogen: .bacteria, severity: 2,
            summary: ["Small dark water-soaked spots on leaves and rough scabby spots on fruit.",
                      "කොළවල කුඩා තද ජලය සහිත ලප සහ ගෙඩිවල රළු පොතු ලප ඇති කරයි.",
                      "இலைகளில் சிறிய கருப்பு நீர்ப்புள்ளிகளையும் பழங்களில் சொரசொரப்பான புள்ளிகளையும் உண்டாக்கும்."],
            symptoms: ["Tiny dark, greasy spots that turn brown with yellow halos", "Spots may fall out leaving a 'shot-hole' look", "Raised scabby spots on fruit", "Leaf drop exposes fruit to sunscald"],
            conditions: "Warm, wet and windy weather; overhead irrigation; infected seed or seedlings.",
            spread: "Splashing water, workers' hands and tools, contaminated seed.",
            organic: ["Remove infected leaves in dry weather only", "Copper-based bactericide on a 7-day schedule", "Do not touch wet plants"],
            chemical: ["Copper hydroxide plus mancozeb tank mix as labelled", "Avoid repeated copper alone – resistance is common"],
            cultural: ["Use certified clean seed", "Drip irrigation instead of overhead", "Disinfect tools", "Rotate with non-solanaceous crops for 2 years"],
            prevention: ["Hot-water seed treatment", "Space plants for quick leaf drying", "Remove volunteer tomatoes"]),
        Disease(
            id: "Tomato___Leaf_Mold", key: "leaf_mold",
            name: ["Leaf Mold", "කොළ පුස් රෝගය", "இலை பூஞ்சை நோய்"],
            scientific: "Passalora fulva", pathogen: .fungus, severity: 2,
            summary: ["Pale spots on top of leaves with olive-green mold beneath, common in humid polytunnels.",
                      "කොළයේ ඉහළ පැත්තේ ලා පැහැති ලප සහ යටි පැත්තේ ඔලිව් පැහැති පුස් ඇති කරයි; ආර්ද්‍ර ග්‍රීන්හවුස්වල සුලභය.",
                      "இலையின் மேல் வெளிர் புள்ளிகளும் அடியில் ஆலிவ் நிற பூஞ்சையும் தோன்றும்; ஈரப்பதமான பசுமைக்குடில்களில் பொதுவானது."],
            symptoms: ["Pale green-yellow spots on upper leaf surface", "Olive-green to grey velvety mold underneath", "Leaves curl, wither and drop", "Rarely affects fruit"],
            conditions: "Humidity above 85% and poor ventilation, typical in polytunnels and dense canopies.",
            spread: "Airborne spores; survive on greenhouse structures and debris.",
            organic: ["Remove affected leaves and increase ventilation", "Sulphur or potassium bicarbonate sprays", "Bacillus subtilis biofungicide"],
            chemical: ["Chlorothalonil or a labelled systemic fungicide", "Rotate modes of action"],
            cultural: ["Open tunnel sides in the morning", "Reduce humidity below 80%", "Wider spacing and pruning"],
            prevention: ["Choose resistant varieties", "Avoid wetting leaves", "Sanitise structures between crops"]),
        Disease(
            id: "Tomato___Septoria_leaf_spot", key: "septoria",
            name: ["Septoria Leaf Spot", "සෙප්ටෝරියා කොළ ලප", "செப்டோரியா இலைப்புள்ளி"],
            scientific: "Septoria lycopersici", pathogen: .fungus, severity: 2,
            summary: ["Many small round spots with dark edges and grey centres that defoliate plants.",
                      "අඳුරු දාරවලින් සහ අළු මැදින් යුත් කුඩා වටකුරු ලප රැසක් කොළ හැලීමට හේතු වේ.",
                      "கருமையான ஓரமும் சாம்பல் நிற மையமும் கொண்ட சிறிய வட்டப் புள்ளிகள் இலைகளை உதிரச் செய்யும்."],
            symptoms: ["Numerous 2–3 mm circular spots with dark borders", "Tiny black dots (fruiting bodies) in spot centres", "Lower leaves yellow and fall", "Fruit rarely infected"],
            conditions: "Warm, humid and rainy periods; dense foliage.",
            spread: "Rain splash from infected debris; hands and tools.",
            organic: ["Remove infected lower leaves", "Copper soap or neem sprays weekly", "Mulch heavily"],
            chemical: ["Chlorothalonil or mancozeb as labelled", "Strobilurin rotation"],
            cultural: ["Stake and prune", "Drip irrigation", "Rotate for 3 years", "Remove weeds (alternate hosts)"],
            prevention: ["Clean seedlings", "Destroy crop residue", "Avoid working in wet plants"]),
        Disease(
            id: "Tomato___Spider_mites Two-spotted_spider_mite", key: "spider_mites",
            name: ["Spider Mites", "මකුළු මයිටාවන්", "சிலந்திப் பேன்"],
            scientific: "Tetranychus urticae", pathogen: .pest, severity: 2,
            summary: ["Tiny sap-sucking mites cause stippled, bronzed leaves and fine webbing in hot dry weather.",
                      "උණුසුම්, වියළි කාලගුණයේදී පැණි උරා බොන කුඩා මයිටාවන් කොළ ලප සහ සිහින් දැල් ඇති කරයි.",
                      "வெப்பமான வறண்ட வானிலையில் சிறிய சாறு உறிஞ்சும் பூச்சிகள் இலைகளில் புள்ளிகளையும் மெல்லிய வலையையும் உண்டாக்கும்."],
            symptoms: ["Fine yellow stippling on leaves", "Bronze, dry or curled leaves", "Fine webbing under leaves and on tips", "Tiny moving dots seen with a hand lens"],
            conditions: "Hot (above 30 °C), dry and dusty conditions; overuse of broad-spectrum insecticides.",
            spread: "Wind, workers, and crawling between touching plants.",
            organic: ["Strong water spray under leaves", "Neem oil or insecticidal soap every 5 days for 3 rounds", "Release predatory mites where available"],
            chemical: ["Use a registered miticide (e.g. abamectin) strictly as labelled", "Rotate chemical groups"],
            cultural: ["Keep plants well watered", "Control dust on paths", "Remove heavily infested leaves"],
            prevention: ["Avoid unnecessary broad-spectrum sprays that kill natural enemies", "Inspect leaf undersides weekly"]),
        Disease(
            id: "Tomato___Target_Spot", key: "target_spot",
            name: ["Target Spot", "ඉලක්ක ලප රෝගය", "இலக்குப் புள்ளி நோய்"],
            scientific: "Corynespora cassiicola", pathogen: .fungus, severity: 2,
            summary: ["Brown spots with target-like rings on leaves, stems and fruit in warm humid weather.",
                      "උණුසුම්, ආර්ද්‍ර කාලගුණයේදී කොළ, කඳ සහ ගෙඩිවල ඉලක්කයක් වැනි වළලු සහිත දුඹුරු ලප ඇති කරයි.",
                      "வெப்பமான ஈரப்பதத்தில் இலை, தண்டு, பழங்களில் இலக்கு போன்ற வளையங்களுடன் பழுப்புப் புள்ளிகள் தோன்றும்."],
            symptoms: ["Brown circular spots with light centres and rings", "Spots merge into large dead patches", "Sunken dark spots on fruit", "Premature leaf drop"],
            conditions: "Warm, humid, prolonged leaf wetness; dense canopies.",
            spread: "Airborne spores and rain splash.",
            organic: ["Remove infected foliage", "Copper-based spray", "Compost mulch and Trichoderma"],
            chemical: ["Chlorothalonil / mancozeb protectants", "Labelled systemic fungicide in rotation"],
            cultural: ["Increase spacing", "Prune for airflow", "Avoid overhead watering"],
            prevention: ["Clean debris", "Rotate with non-hosts", "Scout during humid spells"]),
        Disease(
            id: "Tomato___Tomato_Yellow_Leaf_Curl_Virus", key: "yellow_leaf_curl",
            name: ["Yellow Leaf Curl Virus", "කොළ රැලි වයිරස් රෝගය", "இலை சுருட்டை வைரஸ்"],
            scientific: "Tomato yellow leaf curl virus (TYLCV)", pathogen: .virus, severity: 3,
            summary: ["A whitefly-spread virus causing yellow, upward-curled leaves and stunted plants.",
                      "සුදු මැස්සන් මගින් බෝවන වයිරසයක් වන අතර කොළ කහ වී ඉහළට රැලි වී ශාක කුරු වේ.",
                      "வெள்ளை ஈக்களால் பரவும் வைரஸ்; இலைகள் மஞ்சளாகி மேல்நோக்கி சுருண்டு செடி குன்றும்."],
            symptoms: ["Leaves curl upward and turn yellow at the edges", "Stunted bushy growth", "Flower drop and little or no fruit", "Whiteflies on leaf undersides"],
            conditions: "Hot weather with high whitefly populations; nearby infected crops or weeds.",
            spread: "Silverleaf whitefly (Bemisia tabaci) – not by touch or seed.",
            organic: ["Uproot and bury severely infected plants", "Yellow sticky traps", "Neem or soap sprays against whitefly"],
            chemical: ["Registered systemic insecticide against whitefly only as labelled (no cure for the virus)", "Rotate groups to avoid resistance"],
            cultural: ["Use insect-proof nets on nurseries", "Reflective mulch", "Remove weeds and old crops", "Plant resistant/tolerant varieties"],
            prevention: ["Buy virus-free seedlings", "Keep nursery under net", "Report outbreaks to neighbours quickly"]),
        Disease(
            id: "Tomato___Tomato_mosaic_virus", key: "mosaic",
            name: ["Mosaic Virus", "මොසෙයික් වයිරස් රෝගය", "மொசைக் வைரஸ் நோய்"],
            scientific: "Tomato mosaic virus (ToMV)", pathogen: .virus, severity: 2,
            summary: ["A virus giving mottled light and dark green leaves, spread by hands, tools and seed.",
                      "ලා සහ තද කොළ පැහැති ලප සහිත කොළ ඇති කරන වයිරසයකි; අත්, මෙවලම් සහ බීජ මගින් බෝවේ.",
                      "இலைகளில் வெளிர், கரும் பச்சை திட்டுகளை உண்டாக்கும் வைரஸ்; கைகள், கருவிகள், விதைகள் மூலம் பரவும்."],
            symptoms: ["Mottled light/dark green mosaic pattern", "Distorted, fern-like or narrow leaves", "Stunted growth", "Uneven fruit ripening"],
            conditions: "Handling plants, contaminated tools, tobacco-contaminated hands; infected seed.",
            spread: "Mechanical contact; very stable virus that persists on tools and debris.",
            organic: ["Remove and destroy infected plants", "Wash hands with soap and disinfect tools with 10% bleach", "Do not smoke or use tobacco while handling plants"],
            chemical: ["No chemical cure – chemicals do not control viruses", "Control only by sanitation"],
            cultural: ["Use certified seed", "Disinfect stakes and tools", "Work on healthy plants first", "Rotate and remove weeds"],
            prevention: ["Resistant varieties", "Hygiene stations at field entrances"]),
        Disease(
            id: "Tomato___healthy", key: "healthy",
            name: ["Healthy Leaf", "නිරෝගී කොළය", "ஆரோக்கியமான இலை"],
            scientific: "—", pathogen: .none, severity: 0,
            summary: ["No disease signs detected. Keep up good field hygiene and regular scouting.",
                      "රෝග ලක්ෂණ නොපෙනේ. හොඳ ක්ෂේත්‍ර සනීපාරක්ෂාව සහ නිතිපතා පරීක්ෂාව දිගටම කරගෙන යන්න.",
                      "நோய் அறிகுறிகள் இல்லை. நல்ல வயல் சுகாதாரத்தையும் தொடர் கண்காணிப்பையும் தொடருங்கள்."],
            symptoms: ["Uniform deep-green leaf colour", "No spots, curling, webbing or mold", "Firm, upright growth"],
            conditions: "Balanced nutrition, steady moisture and good airflow.",
            spread: "—",
            organic: [], chemical: [],
            cultural: ["Scout leaves twice a week", "Water at the base in the morning", "Keep tools clean", "Re-scan if the weather turns humid"],
            prevention: ["Rotate crops", "Mulch and stake", "Follow the weather-risk alerts in AgriNova"])
    ]

    static let byLabel: [String: Disease] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static var diseasesOnly: [Disease] { all.filter { !$0.isHealthy } }

    /// Crops of the 38-class PlantVillage dataset that AgriNova does NOT diagnose. Their labels (e.g. "Potato___Early_blight",
    /// "Apple___healthy") must never match a tomato disease just because the disease name is similar.
    private static let otherCrops = ["potato", "apple", "corn", "maize", "grape", "pepper", "cherry", "peach", "orange", "soybean", "squash", "strawberry", "blueberry", "raspberry"]

    /// Tolerant lookup – accepts the raw model label or a short key. Returns nil for other crops.
    static func find(_ label: String) -> Disease? {
        if let d = byLabel[label] { return d }
        let l = label.lowercased()
        if otherCrops.contains(where: { l.contains($0) }) { return nil }
        if let d = all.first(where: { l.contains($0.key.replacingOccurrences(of: "_", with: " ")) || l.contains($0.key) || $0.id.lowercased() == l }) { return d }
        if l.contains("mite") { return byLabel["Tomato___Spider_mites Two-spotted_spider_mite"] }   // e.g. "Two-spotted spider mite"
        return nil
    }
}
