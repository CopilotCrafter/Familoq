// Built-in dish catalogue (about 190 dishes). Ingredients for 4 people in
// German shop terms, so they can go straight onto the shopping list.
//
// cuisine | regions | name | English | German | protein | base | minutes | flags | season | ingredients
//
// protein: vg vegan, v vegetarian, l legumes, e egg, f fish, sf shellfish, p poultry, m beef/lamb, pk pork
// base:    r rice, p pasta/noodles, b bread, po potato, w wholegrain, d dough/dumplings, n none
// flags:   g gluten, d dairy, n nuts, sy soy, hs salty, hf saturated fat, hg sugar/high GI, pu purines,
//          fr fried, pr processed meat, lv offal, raw raw fish/meat, al alcohol, sea seaweed, sw sweet main,
//          vv lots of vegetables, k kid-friendly, lb good cold for a lunchbox, lbo lunchbox only,
//          s1-s3 spicy (mild-hot)
// season:  months, e.g. 4-6 (asparagus) or 11-2
enum DishCatalogueData {
    static let lines: [String] = {
        let groups: [[String]] = [german, indian, italian, greek, turkish, levantine, chinese, japanese,
                                  korean, thai, vietnamese, mexican, spanish, french, lunchbox]
        return groups.flatMap { $0 }
    }()

    static let german: [String] = [
        "de|by,bw|Käsespätzle|Cheese spätzle with fried onions|Spätzle mit Bergkäse und Röstzwiebeln|v|d|35|g,d,hf,hs,k||500 g Spätzle; 250 g Bergkäse; 3 Zwiebeln; 30 g Butter; 1 Kopfsalat",
        "de|bw|Maultaschen in Brühe|Swabian filled pasta in broth|Maultaschen in der Brühe|pk|d|25|g,hs,k||600 g Maultaschen; 1 l Gemüsebrühe; 2 Karotten; 1 Bund Schnittlauch",
        "de|bw|Linsen mit Spätzle und Saitenwürstle|Lentils with spätzle and sausages|Linsen mit Spätzle und Saitenwürstchen|l,pk|d|45|g,pr,hs||300 g Tellerlinsen; 400 g Spätzle; 4 Saitenwürstchen; 1 Zwiebel; 2 Karotten; 2 EL Essig",
        "de|bw|Linsen mit Spätzle (vegetarisch)|Lentils with spätzle, no sausage|Linsen mit Spätzle ohne Wurst|l|d|45|g,vv||300 g Tellerlinsen; 400 g Spätzle; 1 Zwiebel; 2 Karotten; 1 Stange Lauch; 2 EL Essig",
        "de|bw|Gaisburger Marsch|Beef stew with spätzle and potatoes|Rindfleisch-Eintopf mit Spätzle und Kartoffeln|m|d|90|g||500 g Suppenfleisch Rind; 300 g Spätzle; 500 g Kartoffeln; 2 Karotten; 1 Stange Lauch; 1 Zwiebel",
        "de|bw|Flammkuchen|Thin tart with crème fraîche, onion and bacon|Flammkuchen mit Speck und Zwiebeln|pk|d|30|g,d,hf,hs,k||2 Flammkuchenteige; 200 g Crème fraîche; 150 g Speckwürfel; 2 Zwiebeln",
        "de|by|Schweinebraten mit Knödeln|Roast pork with dumplings and sauerkraut|Schweinebraten mit Knödeln und Kraut|pk|d|150|g,hf,hs,al||1,2 kg Schweineschulter; 8 Kartoffelknödel; 1 Glas Sauerkraut; 2 Zwiebeln; 500 ml Dunkelbier",
        "de|by|Obazda mit Brezn|Bavarian cheese spread with pretzels|Obazda mit Brezn und Radieschen|v|b|15|g,d,hf,hs,lb||200 g Camembert; 100 g Frischkäse; 1 Zwiebel; 4 Brezn; 1 Bund Radieschen",
        "de|by|Leberkäs mit Kartoffelsalat|Meat loaf with potato salad|Leberkäse mit Kartoffelsalat|pk|po|30|pr,hs,hf,k||600 g Leberkäse; 1 kg Kartoffeln; 1 Gurke; 1 Zwiebel; 2 EL Senf",
        "de|by|Kaiserschmarrn|Shredded pancake with apple sauce|Kaiserschmarrn mit Apfelmus|v|d|25|g,d,sw,hg,k||250 g Mehl; 4 Eier; 400 ml Milch; 50 g Rosinen; 1 Glas Apfelmus",
        "de|by|Schwammerl mit Semmelknödeln|Creamy mushrooms with bread dumplings|Pilzrahm mit Semmelknödeln|v|d|40|g,d,hf|8-10|600 g Champignons; 8 Semmelknödel; 200 ml Sahne; 1 Zwiebel; 1 Bund Petersilie",
        "de|he|Grüne Soße mit Kartoffeln und Eiern|Frankfurt green herb sauce with potatoes and eggs|Frankfurter Grüne Soße mit Kartoffeln und Eiern|e|po|30|d,vv|3-9|1 Packung Kräuter für Grüne Soße; 300 g Schmand; 250 g Joghurt; 8 Eier; 1 kg Kartoffeln",
        "de|he|Handkäs mit Musik|Sour-milk cheese with onion marinade|Handkäse mit Zwiebel-Marinade und Brot|v|w|15|d,hs,lb||4 Handkäse; 2 Zwiebeln; 4 EL Essig; 4 EL Rapsöl; 4 Scheiben Vollkornbrot",
        "de|he|Frankfurter Rippchen mit Kraut|Cured pork chop with sauerkraut|Rippchen mit Sauerkraut und Kartoffeln|pk|po|60|pr,hs||4 Kasseler-Rippchen; 1 Glas Sauerkraut; 1 kg Kartoffeln; 1 Zwiebel",
        "de|nw|Himmel un Ääd|Potato-apple mash with black pudding|Himmel und Erde mit Blutwurst|pk|po|35|pr,hs,hf||1 kg Kartoffeln; 3 Äpfel; 400 g Blutwurst; 2 Zwiebeln; 200 ml Milch",
        "de|nw|Rheinischer Sauerbraten|Marinated pot roast with raisin sauce|Sauerbraten mit Rotkohl und Klößen|m|po|180|al,hg||1 kg Rinderbraten; 500 ml Rotwein; 250 ml Essig; 50 g Rosinen; 1 Glas Rotkohl; 8 Kartoffelklöße",
        "de|nw|Reibekuchen mit Apfelmus|Potato fritters with apple sauce|Reibekuchen mit Apfelmus|v|po|40|g,fr,k||1,5 kg Kartoffeln; 2 Eier; 2 Zwiebeln; 3 EL Mehl; 1 Glas Apfelmus",
        "de|ni,hb|Grünkohl mit Pinkel|Kale stew with sausage|Grünkohl mit Pinkel und Kartoffeln|pk|po|90|pr,hs,hf,vv|11-2|1 kg Grünkohl; 4 Pinkelwürste; 200 g Kasseler; 1 kg Kartoffeln; 2 Zwiebeln",
        "de|ni|Spargel mit Kartoffeln und Hollandaise|Asparagus with new potatoes and hollandaise|Spargel mit Kartoffeln und Sauce Hollandaise|v|po|35|d,hf,vv|4-6|1,5 kg weißer Spargel; 1 kg neue Kartoffeln; 1 Sauce Hollandaise; 1 Bund Petersilie",
        "de|ni|Spargel mit Kräuterquark|Asparagus with potatoes and herb quark|Spargel mit Kartoffeln und Kräuterquark|v|po|35|d,vv|4-6|1,5 kg Spargel; 1 kg neue Kartoffeln; 500 g Magerquark; 1 Bund Kräuter",
        "de|hh|Labskaus|Corned beef mash with beetroot, herring and egg|Labskaus mit Roter Bete, Rollmops und Spiegelei|m,f,e|po|45|hs,pu||400 g Corned Beef; 1 kg Kartoffeln; 1 Glas Rote Bete; 4 Rollmöpse; 4 Eier; 1 Zwiebel",
        "de|hh,sh|Scholle Finkenwerder Art|Plaice with bacon and potatoes|Scholle mit Speck und Kartoffeln|f,pk|po|35|hs|5-9|4 Schollen; 100 g Speckwürfel; 1 kg Kartoffeln; 1 Gurke; 1 Zitrone",
        "de|hh,sh|Matjes Hausfrauenart|Matjes herring in apple-onion cream|Matjes mit Apfel-Zwiebel-Soße und Pellkartoffeln|f|po|20|d,hs,raw|5-9|8 Matjesfilets; 1 Apfel; 1 Zwiebel; 200 g Schmand; 1 kg Kartoffeln",
        "de|hh|Hamburger Pannfisch|Pan-fried fish with mustard sauce|Pannfisch mit Senfsoße und Bratkartoffeln|f|po|35|d||600 g Seelachsfilet; 1 kg Kartoffeln; 2 Zwiebeln; 3 EL Senf; 200 ml Sahne",
        "de|sh|Birnen, Bohnen und Speck|Pears, green beans and bacon|Birnen, Bohnen und Speck|pk|po|45|pr,hs,vv|7-9|4 Kochbirnen; 750 g grüne Bohnen; 300 g Speck; 1 kg Kartoffeln; 1 Bund Bohnenkraut",
        "de|mv,sh|Ostsee-Fischsuppe|Baltic fish soup with vegetables|Fischsuppe mit Gemüse|f|po|40|vv||600 g Fischfilet; 2 Karotten; 1 Stange Lauch; 500 g Kartoffeln; 1 l Fischfond; 1 Bund Dill",
        "de|be,bb|Königsberger Klopse|Meatballs in caper sauce with rice|Königsberger Klopse mit Reis|m,pk|r|50|g,d||500 g gemischtes Hack; 1 Brötchen; 1 Ei; 2 EL Kapern; 200 ml Sahne; 300 g Reis",
        "de|be|Currywurst mit Ofenkartoffeln|Curry sausage with oven potatoes|Currywurst mit Ofenkartoffeln|pk|po|30|pr,hs,hf,hg,k||8 Bratwürste; 1 Flasche Currysoße; 1 kg Kartoffeln; 1 EL Currypulver",
        "de|be,bb|Kartoffelsuppe mit Majoran|Potato soup with marjoram|Kartoffelsuppe mit Majoran|vg|po|40|vv,k,lb||1 kg Kartoffeln; 2 Karotten; 1 Stange Lauch; 1 Stück Sellerie; 1 l Gemüsebrühe; 1 TL Majoran",
        "de|bb|Pellkartoffeln mit Quark und Leinöl|Potatoes with herb quark and linseed oil|Pellkartoffeln mit Quark und Leinöl|v|po|25|d,vv,lb||1,5 kg Kartoffeln; 750 g Quark; 3 EL Leinöl; 1 Bund Schnittlauch; 1 Gurke",
        "de|sn|Leipziger Allerlei|Mixed spring vegetables|Leipziger Allerlei mit Kartoffeln|v|po|35|d,vv|5-7|300 g Erbsen; 300 g Karotten; 300 g Spargel; 200 g Champignons; 1 Blumenkohl; 800 g Kartoffeln; 30 g Butter",
        "de|sn,th|Quarkkeulchen|Quark-potato pancakes with apple sauce|Quarkkeulchen mit Apfelmus|v|po|35|g,d,fr,sw,k||500 g Kartoffeln; 250 g Quark; 2 Eier; 100 g Mehl; 1 Glas Apfelmus",
        "de|th|Rouladen mit Thüringer Klößen|Beef roulades with potato dumplings|Rinderrouladen mit Thüringer Klößen und Rotkohl|m,pk|po|120|hs,hf||4 Rinderrouladen; 4 Scheiben Speck; 2 Gewürzgurken; 2 Zwiebeln; 8 Thüringer Klöße; 1 Glas Rotkohl",
        "de|th|Rostbratwurst mit Sauerkraut|Grilled sausage with sauerkraut|Rostbratwurst mit Sauerkraut und Brötchen|pk|b|25|pr,hs,hf,k||8 Rostbratwürste; 1 Glas Sauerkraut; 4 Brötchen; 1 Glas Senf",
        "de|st,sn|Soljanka|Sweet-sour meat and pickle soup|Soljanka|pk,m|n|40|pr,hs||200 g Jagdwurst; 200 g Kasseler; 3 Gewürzgurken; 1 Paprika; 2 Zwiebeln; 2 EL Tomatenmark; 1 Zitrone",
        "de|sl|Dibbelabbes|Potato bake with leek and bacon|Kartoffel-Lauch-Pfanne mit Speck|pk|po|60|pr,hf||1,5 kg Kartoffeln; 200 g Speck; 2 Stangen Lauch; 2 Eier; 2 Zwiebeln",
        "de|rp|Pfälzer Leberknödel mit Sauerkraut|Liver dumplings with sauerkraut|Leberknödel mit Sauerkraut und Kartoffeln|pk|po|45|lv,hs,pu||8 Leberknödel; 1 Glas Sauerkraut; 1 kg Kartoffeln; 1 Zwiebel",
        "de|rp,sl|Grumbeersupp mit Quetschekuche|Potato soup with plum cake|Kartoffelsuppe mit Zwetschgenkuchen|vg|po|60|g,sw|8-9|1 kg Kartoffeln; 2 Karotten; 1 Stange Lauch; 1 l Gemüsebrühe; 1 Blech Zwetschgenkuchen",
        "de||Hähnchen-Gemüse-Pfanne mit Naturreis|Chicken and vegetable pan with brown rice|Hähnchen-Gemüse-Pfanne mit Naturreis|p|w|30|vv,k,lb||500 g Hähnchenbrust; 1 Brokkoli; 2 Paprika; 1 Zucchini; 300 g Naturreis; 2 EL Rapsöl",
        "de||Linseneintopf|Lentil stew with vegetables|Linseneintopf mit Gemüse|l|po|45|vv,lb||300 g Tellerlinsen; 3 Karotten; 1 Stange Lauch; 400 g Kartoffeln; 1 Zwiebel; 1 l Gemüsebrühe; 2 EL Essig",
        "de||Erbseneintopf|Split pea soup|Erbseneintopf|l|po|60|vv||400 g getrocknete Schälerbsen; 400 g Kartoffeln; 2 Karotten; 1 Stange Lauch; 1 Zwiebel; 1 l Gemüsebrühe",
        "de||Lachs mit Ofengemüse|Salmon with roast vegetables|Lachs mit Ofengemüse und Kartoffeln|f|po|35|vv,k||4 Lachsfilets; 1 kg Kartoffeln; 2 Zucchini; 2 Paprika; 1 Zitrone; 2 EL Olivenöl",
        "de||Gemüsesuppe mit Vollkornbrot|Vegetable soup with wholegrain bread|Gemüsesuppe mit Vollkornbrot|vg|w|35|g,vv,lb||3 Karotten; 1 Stange Lauch; 1 Stück Sellerie; 300 g Kartoffeln; 200 g grüne Bohnen; 1 l Gemüsebrühe; 1 Vollkornbrot",
        "de||Kohlrouladen|Cabbage rolls with mince|Kohlrouladen mit Kartoffeln|m,pk|po|75|vv,hs|10-3|1 Weißkohl; 500 g gemischtes Hack; 1 Ei; 1 Zwiebel; 1 kg Kartoffeln; 400 ml Gemüsebrühe",
        "de||Rührei mit Spinat und Vollkornbrot|Scrambled eggs with spinach|Rührei mit Spinat und Vollkornbrot|e|w|15|g,vv,k||8 Eier; 300 g Blattspinat; 1 Zwiebel; 1 Vollkornbrot; 250 g Kirschtomaten",
        "de||Fischstäbchen mit Püree und Erbsen|Fish fingers, mash and peas|Fischstäbchen mit Kartoffelpüree und Erbsen|f|po|25|g,d,fr,k||30 Fischstäbchen; 1 kg Kartoffeln; 200 ml Milch; 450 g Erbsen",
        "de||Wirsing-Kartoffel-Auflauf|Savoy cabbage and potato bake|Wirsing-Kartoffel-Auflauf|v|po|50|d,hf,vv|10-3|1 Wirsing; 1 kg Kartoffeln; 200 g Bergkäse; 200 ml Sahne; 1 Zwiebel",
        "de||Kürbissuppe|Pumpkin soup with pumpkin seeds|Kürbissuppe mit Kürbiskernen|vg|n|35|hf,vv,k,lb|9-11|1 Hokkaido-Kürbis; 2 Karotten; 1 Zwiebel; 1 Stück Ingwer; 400 ml Kokosmilch; 50 g Kürbiskerne",
        "de||Bratkartoffeln mit Spiegelei|Fried potatoes with fried egg and salad|Bratkartoffeln mit Spiegelei und Salat|e|po|30|fr,k||1,2 kg Kartoffeln; 8 Eier; 2 Zwiebeln; 1 Kopfsalat; 2 EL Rapsöl",
        "de||Schnitzel mit Kartoffelsalat|Breaded escalope with potato salad|Schnitzel mit Kartoffelsalat|pk|po|40|g,fr,k||4 Schweineschnitzel; 2 Eier; 100 g Paniermehl; 1 kg Kartoffeln; 1 Gurke; 1 Zwiebel",
        "de||Ofenkartoffeln mit Kräuterquark|Baked potatoes with herb quark and salad|Ofenkartoffeln mit Kräuterquark und Salat|v|po|45|d,vv,k||8 große Kartoffeln; 500 g Magerquark; 1 Bund Kräuter; 1 Gurke; 1 Kopfsalat"
    ]

    static let indian: [String] = [
        "in|kl|Avial|Mixed vegetables in coconut-yoghurt sauce|Gemüse in Kokos-Joghurt-Soße mit Reis|v|r|40|d,hf,vv,s1||1 Aubergine; 2 Karotten; 200 g grüne Bohnen; 1 Kochbanane; 150 g Kokosraspeln; 200 g Joghurt; 300 g Reis; 1 Bund Curryblätter",
        "in|kl|Meen Curry|Kerala fish curry with coconut|Kerala-Fischcurry mit Kokosmilch|f|r|35|hf,s2||600 g Seelachsfilet; 400 ml Kokosmilch; 2 Tomaten; 1 Zwiebel; 1 Stück Ingwer; 1 TL Kurkuma; 300 g Reis",
        "in|kl|Kadala Curry mit Puttu|Black chickpea curry with steamed rice cake|Schwarze-Kichererbsen-Curry mit Puttu|l|r|50|vv,s2||300 g schwarze Kichererbsen; 100 g Kokosraspeln; 2 Zwiebeln; 2 Tomaten; 300 g Puttu-Reismehl",
        "in|kl|Appam mit Gemüse-Stew|Rice hoppers with coconut vegetable stew|Appam mit Kokos-Gemüse-Eintopf|vg|r|45|hf,vv,k||300 g Reismehl; 400 ml Kokosmilch; 3 Kartoffeln; 2 Karotten; 150 g Erbsen; 1 Zwiebel",
        "in|kl|Chicken Varutharachathu|Chicken curry with roasted coconut|Hähnchencurry mit gerösteter Kokosnuss|p|r|50|hf,s3||800 g Hähnchenschenkel; 150 g Kokosraspeln; 2 Zwiebeln; 2 Tomaten; 1 Stück Ingwer; 300 g Reis",
        "in|kl,tn|Kohl-Thoran mit Moru|Cabbage with coconut, rice and spiced buttermilk|Kohl mit Kokos, Reis und Gewürz-Buttermilch|v|r|25|d,vv,s1||1 Weißkohl; 100 g Kokosraspeln; 1 TL Senfsamen; 300 g Reis; 500 ml Buttermilch",
        "in|tn|Sambar mit Reis|Lentil-vegetable stew with tamarind|Linsen-Gemüse-Eintopf mit Tamarinde und Reis|l|r|45|vv,s2||200 g Toor Dal; 2 Karotten; 1 Aubergine; 2 Tomaten; 1 EL Sambar-Pulver; 1 EL Tamarindenpaste; 300 g Reis",
        "in|tn|Idli mit Sambar|Steamed rice cakes with sambar and chutney|Idli mit Sambar und Kokos-Chutney|l|r|40|vv,s1,k||500 g Idli-Teig; 200 g Toor Dal; 2 Karotten; 2 Tomaten; 100 g Kokosraspeln; 1 EL Sambar-Pulver",
        "in|tn,ka|Masala Dosa|Crispy rice crepe with potato filling|Masala Dosa mit Kartoffelfüllung|l|r|40|s1,k||500 g Dosa-Teig; 800 g Kartoffeln; 2 Zwiebeln; 1 TL Senfsamen; 100 g Kokosraspeln",
        "in|tn|Rasam mit Reis|Pepper-tamarind soup with rice|Pfeffer-Tamarinden-Suppe mit Reis|l|r|30|vv,s2||100 g Toor Dal; 3 Tomaten; 1 EL Tamarindenpaste; 1 EL Rasam-Pulver; 300 g Reis",
        "in|tn|Chettinad Chicken|Spicy Chettinad chicken curry|Hähnchen nach Chettinad-Art|p|r|50|s3||800 g Hähnchenschenkel; 2 Zwiebeln; 2 Tomaten; 1 EL Fenchelsamen; 50 g Kokosraspeln; 300 g Reis",
        "in|tn|Lemon Rice mit Raita|Lemon rice with cucumber raita|Zitronenreis mit Gurken-Raita|v|r|20|d,n,k,lb||300 g Reis; 2 Zitronen; 50 g Erdnüsse; 1 TL Senfsamen; 1 Gurke; 400 g Joghurt",
        "in|ka|Bisi Bele Bath|Rice, lentil and vegetable one-pot|Reis-Linsen-Gemüse-Topf|l|r|45|vv,s2||200 g Reis; 150 g Toor Dal; 2 Karotten; 150 g Erbsen; 150 g grüne Bohnen; 2 EL Bisi-Bele-Bath-Pulver",
        "in|ka|Ragi Mudde mit Soppu Saaru|Finger millet balls with greens curry|Fingerhirse-Klöße mit Blattgemüse-Curry|l|w|40|vv,s1||300 g Ragi-Mehl; 100 g Toor Dal; 300 g Spinat; 2 Tomaten; 1 Zwiebel",
        "in|ap|Pesarattu|Green moong crepes with ginger chutney|Mungbohnen-Crêpes mit Ingwer-Chutney|l|n|35|vv,s1,lb||300 g grüne Mungbohnen; 1 Stück Ingwer; 2 grüne Chilis; 1 Zwiebel; 1 Bund Koriander",
        "in|ap|Andhra Chicken Curry|Fiery Andhra chicken curry|Scharfes Hähnchencurry nach Andhra-Art|p|r|45|s3||800 g Hähnchenschenkel; 2 Zwiebeln; 2 Tomaten; 2 TL Chilipulver; 1 Stück Ingwer; 300 g Reis",
        "in|tg|Hyderabadi Chicken Biryani|Layered spiced rice with chicken|Hyderabadi-Hähnchen-Biryani|p|r|90|d,hf,s2||800 g Hähnchenschenkel; 400 g Basmatireis; 300 g Joghurt; 3 Zwiebeln; 1 Bund Minze; 50 g Ghee",
        "in|tg|Veg Biryani mit Raita|Vegetable biryani with raita|Gemüse-Biryani mit Raita|v|r|60|d,vv,s1||400 g Basmatireis; 2 Karotten; 200 g grüne Bohnen; 150 g Erbsen; 1 Blumenkohl; 2 Zwiebeln; 400 g Joghurt",
        "in|tg|Khatti Dal|Tangy lentils with rice|Säuerliches Linsencurry mit Reis|l|r|30|vv,s1||250 g Toor Dal; 2 Tomaten; 1 EL Tamarindenpaste; 1 Bund Curryblätter; 300 g Reis",
        "in|mh|Pav Bhaji|Spiced vegetable mash with buttered rolls|Gemüse-Masala mit Butterbrötchen|v|b|40|g,d,hf,s1,k||600 g Kartoffeln; 1 Blumenkohl; 150 g Erbsen; 2 Paprika; 3 Tomaten; 2 EL Pav-Bhaji-Masala; 8 Brötchen; 50 g Butter",
        "in|mh|Misal Pav|Sprouted bean curry with rolls|Keimlings-Curry mit Brötchen|l|b|40|g,s3||300 g Mungkeimlinge; 2 Zwiebeln; 2 Tomaten; 2 EL Misal-Masala; 8 Brötchen",
        "in|mh|Poha|Flattened rice with peas and peanuts|Reisflocken mit Erbsen und Erdnüssen|vg|r|20|n,k,lb||300 g Poha; 1 Zwiebel; 100 g Erbsen; 50 g Erdnüsse; 1 Zitrone; 1 TL Kurkuma",
        "in|mh|Varan Bhaat|Simple dal with rice and ghee|Einfaches Dal mit Reis|l|r|30|k||200 g Toor Dal; 300 g Reis; 1 TL Kurkuma; 1 EL Ghee; 1 Zitrone",
        "in|ga|Goan Fish Curry|Tangy coconut fish curry|Goa-Fischcurry mit Kokos|f|r|35|hf,s2||600 g Seelachsfilet; 400 ml Kokosmilch; 1 EL Tamarindenpaste; 1 Zwiebel; 2 TL Chilipulver; 300 g Reis",
        "in|ga|Chicken Xacuti|Chicken in roasted spice-coconut sauce|Hähnchen-Xacuti|p|r|60|hf,s2||800 g Hähnchenschenkel; 150 g Kokosraspeln; 2 Zwiebeln; 1 EL Mohnsamen; 300 g Reis",
        "in|ga|Prawn Balchão|Spicy tangy prawn curry|Scharfe Garnelen in Essig-Chili-Soße|sf|r|30|hs,pu,s3||500 g Garnelen; 3 Zwiebeln; 3 Tomaten; 4 EL Essig; 300 g Reis",
        "in|gj|Dhokla mit Chutney|Steamed chickpea-flour cake|Gedämpfter Kichererbsenkuchen mit Chutney|l|n|35|d,k,lb||250 g Kichererbsenmehl; 200 g Joghurt; 1 Zitrone; 1 TL Senfsamen; 1 Bund Koriander",
        "in|gj|Undhiyu|Mixed winter vegetables with fenugreek dumplings|Wintergemüse-Topf mit Bockshornklee-Bällchen|l|n|75|fr,vv,s1|11-2|500 g Süßkartoffeln; 300 g Papdi-Bohnen; 1 Aubergine; 200 g Kichererbsenmehl; 1 Bund Bockshornklee",
        "in|gj|Gujarati Dal-Bhaat-Shaak|Sweet-sour dal with rice and vegetables|Süß-saures Dal mit Reis und Gemüse|l|r|40|hg,vv||200 g Toor Dal; 300 g Reis; 1 EL Jaggery; 500 g Okra; 2 Tomaten",
        "in|gj|Thepla mit Joghurt|Fenugreek flatbread with yoghurt|Bockshornklee-Fladenbrot mit Joghurt|v|w|35|g,d,k,lb||300 g Atta; 1 Bund Bockshornklee; 400 g Joghurt; 1 TL Kurkuma",
        "in|rj|Dal Baati Churma|Lentils with baked wheat balls|Linsen mit gebackenen Weizenbällchen|l|w|75|g,d,hf,hg||300 g gemischte Linsen; 400 g Atta; 100 g Ghee; 50 g Jaggery",
        "in|rj|Gatte ki Sabzi|Gram-flour dumplings in yoghurt curry|Kichererbsen-Klößchen in Joghurt-Curry|l|r|45|d,s2||200 g Kichererbsenmehl; 400 g Joghurt; 1 Zwiebel; 1 TL Kurkuma; 300 g Reis",
        "in|rj|Laal Maas|Fiery red mutton curry|Scharfes Lammcurry|m|r|120|hf,s3||800 g Lammschulter; 200 g Joghurt; 3 Zwiebeln; 3 EL Kashmiri-Chili; 50 g Ghee; 300 g Reis",
        "in|pb|Rajma Chawal|Kidney bean curry with rice|Kidneybohnen-Curry mit Reis|l|r|45|vv,k,lb||2 Dosen Kidneybohnen; 2 Zwiebeln; 3 Tomaten; 1 Stück Ingwer; 300 g Reis",
        "in|pb|Chole Bhature|Chickpea curry with fried bread|Kichererbsen-Curry mit frittiertem Brot|l|b|50|g,d,fr,s2||2 Dosen Kichererbsen; 2 Zwiebeln; 3 Tomaten; 2 EL Chana-Masala; 400 g Mehl; 100 g Joghurt",
        "in|pb|Chole mit Vollkorn-Roti|Chickpea curry with wholewheat roti|Kichererbsen-Curry mit Vollkorn-Roti|l|w|45|g,vv,s2,lb||2 Dosen Kichererbsen; 2 Zwiebeln; 3 Tomaten; 2 EL Chana-Masala; 300 g Atta",
        "in|pb|Sarson ka Saag mit Makki di Roti|Mustard greens with maize flatbread|Senfgemüse mit Maisfladen|v|w|60|d,vv|11-2|500 g Senfblätter; 250 g Spinat; 300 g Maismehl; 30 g Butter; 1 Stück Ingwer",
        "in|pb|Butter Chicken mit Naan|Chicken in creamy tomato sauce|Butter Chicken mit Naan|p|b|50|g,d,hf,s1,k||800 g Hähnchenbrust; 400 g passierte Tomaten; 200 ml Sahne; 50 g Butter; 200 g Joghurt; 4 Naan",
        "in|pb|Tandoori Chicken mit Salat|Yoghurt-spiced grilled chicken|Tandoori-Hähnchen mit Salat|p|n|45|d,vv,s2||1 kg Hähnchenschenkel; 300 g Joghurt; 2 EL Tandoori-Masala; 1 Zitrone; 1 Gurke; 2 Tomaten; 1 Zwiebel",
        "in|pb,up|Palak Paneer mit Roti|Spinach with Indian cheese|Spinat mit Paneer und Roti|v|w|35|g,d,hf,vv,s1||600 g Spinat; 400 g Paneer; 1 Zwiebel; 2 Tomaten; 1 Stück Ingwer; 300 g Atta",
        "in|up|Dal Tadka mit Jeera Rice|Yellow lentils with cumin rice|Gelbe Linsen mit Kreuzkümmelreis|l|r|35|vv,k||250 g Moong Dal; 2 Tomaten; 1 Zwiebel; 1 TL Kreuzkümmel; 300 g Basmatireis",
        "in|up|Aloo Gobi mit Roti|Potato and cauliflower curry|Kartoffel-Blumenkohl-Curry mit Roti|vg|w|35|g,vv,s1,lb||1 Blumenkohl; 500 g Kartoffeln; 2 Tomaten; 1 Zwiebel; 1 TL Kurkuma; 300 g Atta",
        "in|up|Baingan Bharta|Smoky mashed aubergine|Rauchiges Auberginen-Püree mit Roti|vg|w|40|g,vv,s1||3 Auberginen; 2 Zwiebeln; 3 Tomaten; 1 Stück Ingwer; 300 g Atta",
        "in|up|Kadhi Pakora|Yoghurt-gram flour curry with fritters|Joghurt-Curry mit Pakoras und Reis|v|r|45|d,fr||500 g Joghurt; 150 g Kichererbsenmehl; 1 Zwiebel; 1 TL Kurkuma; 300 g Reis",
        "in||Gemüse-Khichdi|Rice and lentil porridge with vegetables|Reis-Linsen-Topf mit Gemüse|l|r|30|vv,k||200 g Reis; 150 g Moong Dal; 2 Karotten; 150 g Erbsen; 1 TL Kurkuma; 1 EL Ghee",
        "in|wb|Macher Jhol|Light Bengali fish curry|Leichtes bengalisches Fischcurry|f|r|35|vv,s1||600 g Pangasiusfilet; 2 Kartoffeln; 1 Aubergine; 2 Tomaten; 1 TL Panch Phoron; 300 g Reis",
        "in|wb|Shorshe Maach|Fish in mustard sauce|Fisch in Senfsoße mit Reis|f|r|30|s2||600 g Fischfilet; 3 EL Senfsamen; 2 grüne Chilis; 3 EL Senföl; 300 g Reis",
        "in|wb|Cholar Dal|Bengal gram dal with coconut|Kichererbsen-Dal mit Kokos|l|r|40|k||250 g Chana Dal; 50 g Kokosraspeln; 1 EL Zucker; 1 TL Kreuzkümmel; 300 g Reis",
        "in|wb|Kosha Mangsho|Slow-cooked Bengali mutton|Geschmortes Lamm nach bengalischer Art|m|r|120|hf,s2||800 g Lammschulter; 3 Zwiebeln; 200 g Joghurt; 2 Kartoffeln; 3 EL Senföl; 300 g Reis",
        "in|jk|Rogan Josh|Kashmiri lamb curry|Kaschmir-Lammcurry|m|r|90|d,hf,s2||800 g Lammschulter; 200 g Joghurt; 2 EL Kashmiri-Chili; 1 TL Fenchel; 1 Stück Ingwer; 300 g Reis",
        "in|jk|Kashmiri Dum Aloo|Baby potatoes in yoghurt gravy|Kleine Kartoffeln in Joghurtsoße mit Roti|v|po|45|d,s1,k||800 g kleine Kartoffeln; 300 g Joghurt; 1 EL Kashmiri-Chili; 1 TL Fenchel; 4 Roti",
        "in|br|Litti Chokha|Stuffed wheat balls with smoky vegetable mash|Gefüllte Weizenbällchen mit Gemüsepüree|l|w|60|g,vv,s1||400 g Atta; 200 g Sattu; 2 Auberginen; 4 Tomaten; 3 Kartoffeln",
        "in|od|Dalma|Lentils cooked with vegetables|Linsen mit Gemüse und Reis|l|r|40|vv,k||200 g Toor Dal; 300 g Kürbis; 1 Aubergine; 1 Kochbanane; 1 TL Kreuzkümmel; 300 g Reis",
        "in||Egg Curry|Boiled eggs in onion-tomato gravy|Eier-Curry mit Reis|e|r|30|s1,k||8 Eier; 2 Zwiebeln; 3 Tomaten; 1 Stück Ingwer; 1 TL Garam Masala; 300 g Reis",
        "in||Moong Dal Chilla|Lentil pancakes with yoghurt|Linsen-Pfannkuchen mit Joghurt|l|n|25|d,vv,k,lb||250 g gelbe Moong Dal; 1 Zwiebel; 1 Tomate; 1 Bund Koriander; 200 g Joghurt"
    ]

    static let italian: [String] = [
        "it|emr|Tagliatelle al ragù|Tagliatelle with slow meat sauce|Tagliatelle mit Ragù bolognese|m,pk|p|120|g,d,hs,k||500 g Tagliatelle; 400 g gemischtes Hack; 1 Karotte; 1 Stange Sellerie; 1 Zwiebel; 400 g passierte Tomaten; 50 g Parmesan",
        "it|emr|Tortellini in brodo|Filled pasta in broth|Tortellini in Brühe|pk|p|20|g,d,hs,k||500 g Tortellini; 1,5 l Hühnerbrühe; 50 g Parmesan",
        "it|cam|Pizza Margherita|Homemade Margherita pizza|Pizza Margherita (selbst gemacht)|v|b|60|g,d,k||500 g Mehl; 1 Würfel Hefe; 400 g passierte Tomaten; 250 g Mozzarella; 1 Bund Basilikum",
        "it|cam|Pasta e fagioli|Pasta and bean soup|Nudel-Bohnen-Suppe|l|p|40|g,vv,lb||250 g kurze Nudeln; 2 Dosen Borlottibohnen; 1 Karotte; 1 Stange Sellerie; 1 Zwiebel; 400 g stückige Tomaten",
        "it|cam|Spaghetti alle vongole|Spaghetti with clams|Spaghetti mit Venusmuscheln|sf|p|25|g,pu||500 g Spaghetti; 1 kg Venusmuscheln; 3 Knoblauchzehen; 1 Bund Petersilie; 1 Zitrone",
        "it|sic|Pasta alla Norma|Pasta with aubergine, tomato and ricotta salata|Nudeln mit Aubergine und Tomate|v|p|35|g,d,fr,vv||500 g Rigatoni; 2 Auberginen; 800 g stückige Tomaten; 100 g Ricotta salata; 1 Bund Basilikum",
        "it|sic|Caponata|Sweet-sour aubergine stew with bread|Süß-saures Auberginengemüse mit Brot|vg|b|45|g,vv,lb||3 Auberginen; 2 Stangen Sellerie; 1 Zwiebel; 400 g Tomaten; 2 EL Kapern; 50 g Oliven; 1 Ciabatta",
        "it|tos|Ribollita|Tuscan bread and vegetable soup|Toskanische Brot-Gemüse-Suppe|l|b|60|g,vv|10-3|1 Wirsing; 1 Dose Cannellini-Bohnen; 2 Karotten; 1 Stange Sellerie; 1 Zwiebel; 4 Scheiben altes Brot",
        "it|tos|Pollo alla cacciatora|Hunter's chicken with tomatoes and olives|Jäger-Hähnchen mit Tomaten und Oliven|p|po|60|vv||1,2 kg Hähnchenteile; 400 g Tomaten; 1 Zwiebel; 2 Paprika; 50 g Oliven; 1 kg Kartoffeln",
        "it|lig|Trofie al pesto|Pasta with pesto, beans and potatoes|Nudeln mit Pesto, Bohnen und Kartoffeln|v|p|25|g,d,n,k||500 g Trofie; 1 Glas Pesto Genovese; 200 g grüne Bohnen; 2 Kartoffeln",
        "it|laz|Spaghetti carbonara|Spaghetti with egg, pecorino and guanciale|Spaghetti Carbonara|pk,e|p|25|g,d,hf,hs,k||500 g Spaghetti; 150 g Guanciale; 4 Eier; 80 g Pecorino",
        "it|lom|Risotto alla milanese|Saffron risotto|Safranrisotto|v|r|35|d,hf||350 g Risottoreis; 1 l Gemüsebrühe; 1 Döschen Safran; 50 g Parmesan; 30 g Butter; 1 Zwiebel",
        "it|ven|Risi e bisi|Rice and peas|Reis mit Erbsen|v|r|35|d,k|5-6|300 g Risottoreis; 500 g Erbsen; 1 Zwiebel; 50 g Parmesan; 1 l Gemüsebrühe",
        "it|pug|Orecchiette con cime di rapa|Orecchiette with broccoli rabe|Orecchiette mit Stängelkohl|vg|p|30|g,vv|11-3|500 g Orecchiette; 800 g Cime di rapa; 3 Knoblauchzehen; 1 Chilischote; 4 EL Olivenöl",
        "it||Minestrone|Vegetable soup with pasta and beans|Gemüsesuppe mit Nudeln und Bohnen|vg|p|45|g,vv,k,lb||2 Karotten; 1 Zucchini; 1 Stange Lauch; 1 Dose Cannellini-Bohnen; 400 g Tomaten; 150 g kleine Nudeln",
        "it||Gemüselasagne|Vegetable lasagne|Gemüselasagne|v|p|75|g,d,hf,vv,k||250 g Lasagneplatten; 2 Zucchini; 2 Paprika; 1 Aubergine; 800 g passierte Tomaten; 250 g Mozzarella; 250 g Ricotta",
        "it||Fisch in Tomatensugo mit Polenta|Fish in tomato sauce with polenta|Fisch in Tomatensoße mit Polenta|f|w|35|vv||600 g Kabeljaufilet; 800 g stückige Tomaten; 50 g Oliven; 2 EL Kapern; 250 g Polenta",
        "it|tos|Panzanella|Tuscan bread salad|Toskanischer Brotsalat|vg|b|20|g,vv,lb|6-9|6 Tomaten; 1 Gurke; 1 rote Zwiebel; 1 Ciabatta; 1 Bund Basilikum; 4 EL Olivenöl",
        "it||Frittata mit Gemüse|Vegetable omelette|Gemüse-Frittata|e|n|25|d,vv,k,lb||8 Eier; 1 Zucchini; 1 Paprika; 1 Zwiebel; 50 g Parmesan",
        "it|lom|Risotto ai funghi|Mushroom risotto|Pilzrisotto|v|r|40|d,hf|9-11|350 g Risottoreis; 400 g Champignons; 1 Zwiebel; 1 l Gemüsebrühe; 50 g Parmesan"
    ]

    static let greek: [String] = [
        "gr||Gemista|Stuffed peppers and tomatoes with rice|Gefüllte Paprika und Tomaten mit Reis|vg|r|75|vv|6-9|4 Paprika; 4 große Tomaten; 200 g Reis; 1 Zwiebel; 1 Bund Petersilie; 1 Bund Minze; 500 g Kartoffeln",
        "gr||Fasolada|White bean soup|Weiße-Bohnen-Suppe|l|b|60|vv,lb||2 Dosen weiße Bohnen; 2 Karotten; 2 Stangen Sellerie; 1 Zwiebel; 400 g Tomaten; 4 EL Olivenöl",
        "gr||Moussaka|Aubergine and minced meat bake|Auberginen-Hackfleisch-Auflauf|m|po|90|g,d,hf||3 Auberginen; 500 g Rinderhack; 800 g Tomaten; 500 ml Milch; 50 g Mehl; 50 g Butter; 3 Kartoffeln",
        "gr|crete|Dakos|Barley rusk with tomato and feta|Gerstenzwieback mit Tomate und Feta|v|w|10|g,d,hs,lb|6-9|8 Gerstenzwiebacke; 4 Tomaten; 200 g Feta; 50 g Oliven; 1 Bund Oregano",
        "gr||Hähnchen-Souvlaki mit Tzatziki|Chicken skewers with tzatziki|Hähnchenspieße mit Tzatziki und Salat|p|b|35|g,d,k||800 g Hähnchenbrust; 500 g Joghurt; 1 Gurke; 2 Knoblauchzehen; 4 Pitabrote; 2 Tomaten; 1 Zwiebel",
        "gr||Psari plaki|Baked fish with tomatoes and onions|Fisch aus dem Ofen mit Tomaten und Zwiebeln|f|po|45|vv||800 g Kabeljaufilet; 4 Tomaten; 2 Zwiebeln; 1 kg Kartoffeln; 1 Bund Petersilie",
        "gr||Spanakopita|Spinach and feta pie|Spinat-Feta-Kuchen|v|d|60|g,d,hf,lb||1 Packung Filoteig; 800 g Spinat; 300 g Feta; 2 Eier; 1 Bund Dill",
        "gr||Fakes|Greek lentil soup|Griechische Linsensuppe|l|b|45|vv||300 g braune Linsen; 1 Zwiebel; 2 Karotten; 400 g Tomaten; 2 Lorbeerblätter; 2 EL Essig"
    ]

    static let turkish: [String] = [
        "tr||Mercimek Çorbası|Red lentil soup|Rote-Linsen-Suppe|l|b|30|vv,k,lb||300 g rote Linsen; 1 Zwiebel; 1 Karotte; 1 Kartoffel; 1 EL Paprikamark; 1 Zitrone",
        "tr|ege|İmam Bayıldı|Stuffed aubergines in olive oil|Gefüllte Auberginen in Olivenöl|vg|b|60|g,vv|6-9|4 Auberginen; 3 Zwiebeln; 4 Tomaten; 1 Bund Petersilie; 6 EL Olivenöl; 1 Fladenbrot",
        "tr|gaz|Köfte mit Bulgur|Meatballs with bulgur pilaf|Köfte mit Bulgur und Salat|m|w|40|g||500 g Rinderhack; 1 Zwiebel; 300 g Bulgur; 2 Tomaten; 2 Paprika; 1 Gurke",
        "tr||Menemen|Eggs with peppers and tomatoes|Rührei mit Paprika und Tomaten|e|b|20|g,vv,k,lb||8 Eier; 3 grüne Paprika; 4 Tomaten; 1 Zwiebel; 1 Fladenbrot",
        "tr||Kuru Fasulye|White bean stew with rice|Weiße-Bohnen-Eintopf mit Reis|l|r|45|vv||2 Dosen weiße Bohnen; 1 Zwiebel; 2 EL Tomatenmark; 1 EL Paprikamark; 300 g Reis",
        "tr|ege|Zeytinyağlı Taze Fasulye|Green beans in olive oil|Grüne Bohnen in Olivenöl mit Brot|vg|b|45|g,vv,lb|6-9|800 g grüne Bohnen; 2 Zwiebeln; 3 Tomaten; 5 EL Olivenöl; 1 Fladenbrot",
        "tr|kar|Hamsi Tava|Pan-fried Black Sea anchovies|Gebratene Sardellen mit Salat|f|b|30|fr,pu|11-2|800 g frische Sardellen; 100 g Maismehl; 1 Zitrone; 1 rote Zwiebel; 1 Bund Petersilie",
        "tr||Lahmacun mit Salat|Thin flatbread with spiced mince|Türkische Pizza mit Salat|m|b|45|g,hs,k||500 g Mehl; 300 g Rinderhack; 2 Tomaten; 1 Paprika; 1 Zwiebel; 1 Bund Petersilie; 1 Zitrone",
        "tr|ist|Tavuk Şiş|Chicken skewers with salad and rice|Hähnchenspieße mit Salat und Reis|p|r|35|d,vv||800 g Hähnchenbrust; 300 g Joghurt; 2 Paprika; 1 Gurke; 3 Tomaten; 250 g Reis"
    ]

    static let levantine: [String] = [
        "lv|leb|Mujaddara|Lentils and rice with crispy onions|Linsen mit Reis und Röstzwiebeln|l|r|45|d,vv,lb||250 g braune Linsen; 200 g Reis; 4 Zwiebeln; 1 TL Kreuzkümmel; 500 g Joghurt",
        "lv|leb|Falafel mit Hummus|Falafel with hummus and salad|Falafel mit Hummus und Salat|l|b|40|g,fr,k,lb||400 g getrocknete Kichererbsen; 1 Bund Petersilie; 1 Zwiebel; 200 g Hummus; 4 Pitabrote; 2 Tomaten; 1 Gurke",
        "lv|leb|Tabbouleh mit Hähnchen|Parsley-bulgur salad with grilled chicken|Petersilien-Bulgur-Salat mit Hähnchen|p|w|30|g,vv,lb||3 Bund Petersilie; 1 Bund Minze; 100 g Bulgur; 4 Tomaten; 2 Zitronen; 600 g Hähnchenbrust",
        "lv|syr|Fattoush|Crispy bread salad with sumac|Brotsalat mit Sumach|vg|b|20|g,vv,lb|5-9|1 Römersalat; 2 Tomaten; 1 Gurke; 1 Bund Radieschen; 2 Pitabrote; 1 EL Sumach",
        "lv|pal|Maqluba|Upside-down rice with chicken and vegetables|Gestürzter Reis mit Hähnchen und Gemüse|p|r|90|n,fr,vv||800 g Hähnchenschenkel; 400 g Reis; 1 Aubergine; 1 Blumenkohl; 2 Kartoffeln; 50 g Pinienkerne",
        "lv||Shakshuka|Eggs in spiced tomato sauce|Eier in würziger Tomatensoße|e|b|25|g,vv,k||8 Eier; 800 g stückige Tomaten; 2 Paprika; 1 Zwiebel; 1 TL Kreuzkümmel; 1 Fladenbrot",
        "lv||Fisch mit Tahini-Soße|Fish with tahini sauce and bulgur|Fisch mit Tahini-Soße und Bulgur|f|w|30|g,vv||800 g Fischfilet; 100 g Tahini; 2 Zitronen; 250 g Bulgur; 1 Bund Petersilie"
    ]

    static let chinese: [String] = [
        "cn|sc|Mapo Tofu|Spicy tofu with minced pork|Scharfer Tofu mit Hackfleisch und Reis|l,pk|r|25|sy,hs,s3||600 g Seidentofu; 150 g Schweinehack; 2 EL Doubanjiang; 1 TL Szechuanpfeffer; 300 g Reis",
        "cn|sc|Gong Bao Hähnchen|Kung pao chicken with peanuts|Kung-Pao-Hähnchen mit Reis|p|r|25|n,sy,hs,s2||600 g Hähnchenbrust; 80 g Erdnüsse; 2 Paprika; 4 Frühlingszwiebeln; 3 EL Sojasoße; 300 g Reis",
        "cn|sc|Yuxiang Qiezi|Aubergine in garlic-chilli sauce|Auberginen in Knoblauch-Chili-Soße|vg|r|30|sy,hs,fr,s2||3 Auberginen; 4 Knoblauchzehen; 1 Stück Ingwer; 2 EL Chilibohnenpaste; 300 g Reis",
        "cn|gd|Gedämpfter Fisch mit Ingwer|Steamed fish with ginger and spring onions|Gedämpfter Fisch mit Ingwer und Pak Choi|f|r|25|sy,vv||800 g Wolfsbarschfilet; 1 Stück Ingwer; 1 Bund Frühlingszwiebeln; 3 EL Sojasoße; 300 g Reis; 500 g Pak Choi",
        "cn|gd|Wantan-Nudelsuppe|Wonton noodle soup|Wantan-Nudelsuppe|pk,sf|p|40|g,sy,hs,k||30 Wantan-Blätter; 300 g Schweinehack; 200 g Garnelen; 300 g Eiernudeln; 1,5 l Hühnerbrühe; 300 g Pak Choi",
        "cn|gd|Char Siu|Cantonese BBQ pork with rice and greens|Kantonesischer Schweinebraten mit Reis|pk|r|60|sy,hg,hs||800 g Schweinenacken; 4 EL Hoisinsoße; 2 EL Honig; 300 g Reis; 500 g Pak Choi",
        "cn|hn|Hunan-Schweinefleisch mit Chili|Stir-fried pork with green chillies|Schweinefleisch mit grünen Chilis|pk|r|25|sy,hs,s3||500 g Schweinebauch; 6 grüne Chilis; 3 Knoblauchzehen; 2 EL Sojasoße; 300 g Reis",
        "cn|js|Tomaten-Ei-Pfanne|Tomato and egg stir-fry with rice|Tomaten-Rührei mit Reis|e|r|15|vv,k||8 Eier; 6 Tomaten; 3 Frühlingszwiebeln; 1 EL Zucker; 300 g Reis",
        "cn|sd|Jiaozi|Pork and cabbage dumplings|Chinesische Teigtaschen|pk|d|60|g,sy,k||500 g Mehl; 400 g Schweinehack; 300 g Chinakohl; 1 Stück Ingwer; 4 EL Sojasoße",
        "cn||Gebratener Reis mit Gemüse und Ei|Vegetable egg fried rice|Gebratener Reis mit Gemüse und Ei|e|r|20|sy,k,lb||400 g Reis; 4 Eier; 200 g Erbsen; 2 Karotten; 4 Frühlingszwiebeln; 3 EL Sojasoße",
        "cn||Rindfleisch mit Brokkoli|Beef and broccoli stir-fry|Rindfleisch mit Brokkoli und Reis|m|r|25|sy,hs,vv||500 g Rinderhüfte; 2 Brokkoli; 3 EL Austernsoße; 1 Stück Ingwer; 300 g Reis",
        "cn|sc|Sauer-scharfe Suppe|Hot and sour soup with tofu|Sauer-scharfe Suppe mit Tofu|l,e|n|30|sy,hs,vv,s2||300 g Tofu; 200 g Shiitake; 1 Dose Bambussprossen; 2 Eier; 3 EL Reisessig; 1 l Gemüsebrühe"
    ]

    static let japanese: [String] = [
        "jp||Teriyaki-Lachs|Teriyaki salmon with rice and vegetables|Teriyaki-Lachs mit Reis und Gemüse|f|r|25|sy,hs,hg,k||4 Lachsfilets; 4 EL Teriyakisoße; 300 g Reis; 1 Brokkoli; 2 Karotten",
        "jp|kansai|Okonomiyaki|Savoury cabbage pancake|Japanischer Kohlpfannkuchen|pk,e|n|30|g,sy,hs||1/2 Weißkohl; 200 g Mehl; 4 Eier; 150 g Bacon; 4 EL Okonomiyakisoße",
        "jp||Misosuppe mit Tofu und Reis|Miso soup with tofu and rice|Misosuppe mit Tofu und Reis|l|r|20|sy,hs,sea,lb||4 EL Misopaste; 300 g Tofu; 1 Päckchen Wakame; 4 Frühlingszwiebeln; 300 g Reis",
        "jp||Oyakodon|Chicken and egg rice bowl|Hähnchen-Ei-Reisschale|p,e|r|25|sy,hs,k||500 g Hähnchenschenkel; 6 Eier; 1 Zwiebel; 4 EL Sojasoße; 2 EL Mirin; 300 g Reis",
        "jp|kyushu|Tonkotsu-Ramen|Pork-bone ramen|Ramen mit Schweinebrühe|pk,e|p|60|g,sy,hs,hf||400 g Ramennudeln; 1,5 l Schweinebrühe; 300 g Schweinebauch; 4 Eier; 4 Frühlingszwiebeln; 1 Päckchen Nori",
        "jp||Sushi-Bowl mit gegartem Lachs|Sushi bowl with cooked salmon and avocado|Sushi-Bowl mit gegartem Lachs und Avocado|f|r|30|sy,sea,vv,k||300 g Sushireis; 400 g Lachsfilet; 2 Avocados; 1 Gurke; 2 Karotten; 1 Päckchen Nori",
        "jp||Yasai Itame|Stir-fried vegetables with rice|Gebratenes Gemüse mit Reis|vg|r|20|sy,vv,lb||1/2 Weißkohl; 2 Karotten; 200 g Sojasprossen; 200 g Pilze; 3 EL Sojasoße; 300 g Reis",
        "jp|hokkaido|Ishikari Nabe|Salmon and miso hot pot|Lachs-Miso-Eintopf|f,l|po|35|sy,hs,vv|10-3|600 g Lachsfilet; 300 g Tofu; 1/2 Chinakohl; 2 Kartoffeln; 4 EL Misopaste"
    ]

    static let korean: [String] = [
        "kr||Bibimbap|Rice bowl with vegetables, egg and chilli paste|Reisschale mit Gemüse und Ei|e|r|40|sy,vv,s2||300 g Reis; 300 g Spinat; 200 g Sojasprossen; 2 Karotten; 1 Zucchini; 4 Eier; 3 EL Gochujang",
        "kr||Kimchi-Jjigae|Kimchi stew with tofu|Kimchi-Eintopf mit Tofu|l,pk|r|30|sy,hs,s3||400 g Kimchi; 300 g Tofu; 150 g Schweinebauch; 1 Zwiebel; 2 EL Gochugaru; 300 g Reis",
        "kr||Bulgogi|Marinated beef with rice and lettuce|Mariniertes Rindfleisch mit Reis und Salat|m|r|30|sy,hg,hs||600 g Rinderhüfte; 4 EL Sojasoße; 1 Birne; 3 Knoblauchzehen; 300 g Reis; 1 Kopfsalat",
        "kr||Japchae|Glass noodles with vegetables|Glasnudeln mit Gemüse|vg|p|35|sy,vv,lb||300 g Glasnudeln; 300 g Spinat; 2 Karotten; 200 g Pilze; 1 Paprika; 3 EL Sojasoße",
        "kr||Sundubu-Jjigae|Soft tofu stew with seafood|Weicher-Tofu-Eintopf mit Meeresfrüchten|l,sf|r|30|sy,hs,s2||600 g Seidentofu; 200 g Garnelen; 200 g Miesmuscheln; 2 Eier; 2 EL Gochugaru; 300 g Reis"
    ]

    static let thai: [String] = [
        "th|central|Grünes Curry mit Hähnchen|Green curry with chicken|Grünes Thai-Curry mit Hähnchen|p|r|30|hf,vv,s2||600 g Hähnchenbrust; 400 ml Kokosmilch; 2 EL grüne Currypaste; 1 Aubergine; 200 g Zuckerschoten; 300 g Jasminreis",
        "th|central|Pad Thai|Stir-fried rice noodles with egg and peanuts|Gebratene Reisnudeln mit Garnelen|e,sf|p|30|n,sy,hs,hg,k||300 g Reisnudeln; 200 g Garnelen; 3 Eier; 200 g Sojasprossen; 50 g Erdnüsse; 2 EL Tamarindenpaste; 3 EL Fischsoße",
        "th|isan|Larb Gai|Minced chicken salad with herbs|Hähnchen-Hack-Salat mit Kräutern und Klebreis|p|r|25|hs,vv,s3||600 g Hähnchenhack; 2 Limetten; 1 Bund Minze; 1 Bund Koriander; 3 EL Fischsoße; 300 g Klebreis",
        "th|isan|Som Tam mit Hähnchen|Green papaya salad with grilled chicken|Papayasalat mit gegrilltem Hähnchen|p|n|30|n,hs,vv,s3||1 grüne Papaya; 200 g Kirschtomaten; 50 g Erdnüsse; 2 Limetten; 3 EL Fischsoße; 600 g Hähnchenschenkel",
        "th|north|Khao Soi|Northern curry noodle soup|Curry-Nudelsuppe nach nordthailändischer Art|p|p|40|g,hf,s2||400 g Eiernudeln; 600 g Hähnchenschenkel; 400 ml Kokosmilch; 2 EL rote Currypaste; 2 Schalotten; 1 Limette",
        "th|south|Massaman-Curry|Mild curry with potatoes and peanuts|Massaman-Curry mit Rind und Kartoffeln|m|r|60|n,hf,k||600 g Rindergulasch; 400 ml Kokosmilch; 3 EL Massaman-Currypaste; 500 g Kartoffeln; 50 g Erdnüsse; 300 g Jasminreis",
        "th||Tom Yum Goong|Hot and sour prawn soup|Scharf-saure Garnelensuppe|sf|n|25|hs,pu,vv,s3||400 g Garnelen; 200 g Champignons; 2 Stängel Zitronengras; 1 Stück Galgant; 2 Limetten; 3 EL Fischsoße",
        "th||Pad Kra Pao|Holy basil stir-fry with fried egg|Hähnchen mit Thai-Basilikum und Spiegelei|p,e|r|20|sy,hs,s2||500 g Hähnchenhack; 1 Bund Thai-Basilikum; 4 Knoblauchzehen; 4 Eier; 2 EL Austernsoße; 300 g Jasminreis"
    ]

    static let vietnamese: [String] = [
        "vn|north|Phở Gà|Chicken noodle soup with herbs|Hühner-Nudelsuppe mit Kräutern|p|p|60|hs,vv,k||400 g Reisbandnudeln; 800 g Hähnchenschenkel; 1 Zwiebel; 1 Stück Ingwer; 2 Sternanis; 200 g Sojasprossen; 1 Bund Thai-Basilikum",
        "vn|central|Bún bò Huế|Spicy beef noodle soup|Scharfe Rindfleisch-Nudelsuppe|m|p|90|hs,s2||400 g Reisnudeln; 600 g Rinderhesse; 3 Stängel Zitronengras; 2 EL Chilipaste; 3 EL Fischsoße",
        "vn|south|Gỏi cuốn|Fresh rice paper rolls with prawns|Sommerrollen mit Garnelen|sf|p|35|vv,k,lb|5-9|1 Packung Reispapier; 300 g Garnelen; 100 g Reisnudeln; 1 Kopfsalat; 1 Bund Minze; 1 Gurke",
        "vn|south|Cá kho tộ|Caramelised fish in a clay pot|Karamellisierter Fisch mit Reis|f|r|40|hs,hg||600 g Pangasiusfilet; 3 EL Fischsoße; 2 EL Zucker; 3 Schalotten; 300 g Reis",
        "vn||Bún chay|Rice noodle salad with tofu|Reisnudelsalat mit Tofu|l|p|30|n,sy,vv,lb||300 g Reisnudeln; 400 g Tofu; 1 Gurke; 2 Karotten; 1 Bund Minze; 50 g Erdnüsse"
    ]

    static let mexican: [String] = [
        "mx||Chili sin Carne|Bean and vegetable chilli with rice|Bohnen-Gemüse-Chili mit Reis|l|r|40|vv,lb,s2||2 Dosen Kidneybohnen; 1 Dose Mais; 2 Paprika; 800 g stückige Tomaten; 1 Zwiebel; 300 g Reis",
        "mx||Hähnchen-Fajitas|Chicken fajitas with peppers|Hähnchen-Fajitas mit Paprika|p|b|30|g,d,vv,k||600 g Hähnchenbrust; 3 Paprika; 2 Zwiebeln; 8 Tortillas; 200 g Joghurt; 1 Avocado",
        "mx|yuc|Cochinita Pibil|Citrus-achiote pulled pork tacos|Zitrus-Schweinefleisch in Tortillas|pk|b|180|hs||1,2 kg Schweineschulter; 3 Orangen; 2 Limetten; 3 EL Achiotepaste; 12 Maistortillas; 2 rote Zwiebeln",
        "mx|oax|Enfrijoladas|Tortillas in black bean sauce|Tortillas in Schwarzbohnensoße|l|b|30|d,vv||2 Dosen schwarze Bohnen; 12 Maistortillas; 100 g Feta; 1 Zwiebel; 1 Avocado",
        "mx|cdmx|Fisch-Tacos mit Krautsalat|Fish tacos with slaw|Fisch-Tacos mit Krautsalat|f|b|30|d,vv,k||600 g Kabeljaufilet; 12 Maistortillas; 1/4 Rotkohl; 2 Limetten; 200 g Joghurt; 1 Avocado",
        "mx||Burrito-Bowl|Rice bowl with beans, corn and salsa|Burrito-Schüssel mit Bohnen und Mais|l|r|30|vv,lb,k||300 g Reis; 1 Dose schwarze Bohnen; 1 Dose Mais; 3 Tomaten; 1 Avocado; 1 Limette"
    ]

    static let spanish: [String] = [
        "es|val|Paella mixta|Seafood and chicken paella|Paella mit Meeresfrüchten und Hähnchen|sf,p|r|60|pu||350 g Paellareis; 400 g Hähnchenschenkel; 300 g Garnelen; 300 g Miesmuscheln; 1 Paprika; 150 g Erbsen; 1 Döschen Safran",
        "es|and|Gazpacho|Cold tomato soup with bread|Kalte Tomatensuppe mit Brot|vg|b|15|g,vv,lb|6-9|1 kg Tomaten; 1 Gurke; 1 Paprika; 1 Knoblauchzehe; 4 EL Olivenöl; 1 Baguette",
        "es||Tortilla española|Potato omelette with salad|Kartoffel-Tortilla mit Salat|e|po|40|k,lb||800 g Kartoffeln; 8 Eier; 1 Zwiebel; 1 Kopfsalat; 4 EL Olivenöl",
        "es|gal|Merluza a la gallega|Hake with paprika potatoes|Seehecht mit Paprika-Kartoffeln|f|po|35|vv||800 g Seehechtfilet; 1 kg Kartoffeln; 2 TL Paprikapulver; 3 Knoblauchzehen; 4 EL Olivenöl",
        "es|and,cat|Espinacas con garbanzos|Spinach with chickpeas|Spinat mit Kichererbsen und Brot|l|b|25|g,vv,lb||2 Dosen Kichererbsen; 500 g Spinat; 3 Knoblauchzehen; 1 TL Paprikapulver; 1 Baguette",
        "es|bas|Marmitako|Basque tuna and potato stew|Thunfisch-Kartoffel-Eintopf|f|po|45|vv|6-9|600 g Thunfischsteak; 1 kg Kartoffeln; 2 Paprika; 1 Zwiebel; 400 g Tomaten"
    ]

    static let french: [String] = [
        "fr|pro|Ratatouille|Provençal vegetable stew with baguette|Provenzalisches Gemüse mit Baguette|vg|b|50|g,vv,lb|6-9|2 Zucchini; 1 Aubergine; 2 Paprika; 4 Tomaten; 1 Zwiebel; 1 Bund Thymian; 1 Baguette",
        "fr|bre|Galettes complètes|Buckwheat crêpes with ham, egg and cheese|Buchweizen-Galettes mit Schinken, Ei und Käse|pk,e|w|30|d,pr,hs,k||250 g Buchweizenmehl; 6 Eier; 150 g gekochter Schinken; 150 g Emmentaler",
        "fr|als|Choucroute garnie|Sauerkraut with sausages and pork|Sauerkraut mit Würsten und Kasseler|pk|po|90|pr,hs,hf,al|10-3|1 kg Sauerkraut; 4 Straßburger Würstchen; 400 g Kasseler; 200 g Speck; 1 kg Kartoffeln; 200 ml Riesling",
        "fr|bur|Bœuf bourguignon|Beef stewed in red wine|Rindfleisch in Rotwein|m|po|180|al,hf||1 kg Rindergulasch; 750 ml Rotwein; 200 g Speck; 250 g Champignons; 3 Karotten; 1 kg Kartoffeln",
        "fr|lyo|Lentilles du Puy mit Lachs|Green lentils with salmon|Grüne Linsen mit Lachs|f,l|n|35|vv||300 g Puy-Linsen; 4 Lachsfilets; 2 Karotten; 1 Schalotte; 1 Bund Petersilie; 2 EL Senf",
        "fr||Quiche aux légumes|Vegetable quiche|Gemüse-Quiche|v|d|60|g,d,hf,lb||1 Mürbeteig; 4 Eier; 200 ml Sahne; 1 Brokkoli; 1 Stange Lauch; 100 g Gruyère",
        "fr||Soupe à l'oignon|French onion soup with cheese toast|Französische Zwiebelsuppe mit Käsetoast|v|b|60|g,d,hs||1 kg Zwiebeln; 1 l Gemüsebrühe; 1 Baguette; 150 g Gruyère; 30 g Butter",
        "fr||Poulet rôti|Roast chicken with roasted vegetables|Brathähnchen mit Ofengemüse|p|po|90|vv,k||1 Hähnchen; 1 kg Kartoffeln; 4 Karotten; 2 Zwiebeln; 1 Bund Thymian"
    ]

    /// School and work lunches that are not suggested for dinner.
    static let lunchbox: [String] = [
        "de||Vollkornbrot mit Frischkäse und Gemüsesticks|Wholegrain sandwich with cream cheese and vegetable sticks|Vollkornbrot mit Frischkäse und Gemüsesticks|v|w|10|g,d,k,lb,lbo||1 Vollkornbrot; 200 g Frischkäse; 1 Gurke; 2 Karotten; 1 Paprika",
        "de||Nudelsalat mit Gemüse und Feta|Pasta salad with vegetables and feta|Nudelsalat mit Gemüse und Feta|v|p|20|g,d,k,lb,lbo||300 g Vollkornnudeln; 200 g Feta; 1 Gurke; 250 g Kirschtomaten; 1 Paprika",
        "de||Linsensalat mit Paprika|Lentil salad with peppers|Linsensalat mit Paprika|l|n|25|vv,lb,lbo||250 g Berglinsen; 2 Paprika; 1 rote Zwiebel; 1 Bund Petersilie; 3 EL Essig",
        "de||Overnight Oats mit Obst|Overnight oats with fruit and nuts|Overnight Oats mit Obst und Nüssen|v|w|5|d,n,k,lb,lbo||200 g Haferflocken; 500 g Joghurt; 2 Äpfel; 1 Schale Beeren; 50 g Walnüsse",
        "lv||Vollkorn-Wrap mit Hummus|Wholegrain wrap with hummus and vegetables|Vollkorn-Wrap mit Hummus und Gemüse|l|w|10|g,k,lb,lbo||4 Vollkorn-Wraps; 200 g Hummus; 1 Gurke; 2 Karotten; 1 Kopfsalat",
        "in||Kathi Roll mit Paneer|Flatbread roll with spiced paneer|Fladenbrot-Rolle mit Paneer|v|w|25|g,d,lb,lbo,s1||4 Chapatis; 300 g Paneer; 1 Paprika; 1 Zwiebel; 150 g Joghurt",
        "jp||Onigiri mit Lachs|Rice balls with salmon|Reisbällchen mit Lachs|f|r|30|sea,k,lb,lbo||300 g Sushireis; 200 g Lachsfilet; 1 Päckchen Nori; 1 Gurke",
        "gr||Couscous-Salat mit Kichererbsen|Couscous salad with chickpeas|Couscous-Salat mit Kichererbsen|l|w|15|g,vv,lb,lbo||200 g Vollkorn-Couscous; 1 Dose Kichererbsen; 1 Gurke; 250 g Kirschtomaten; 1 Zitrone; 1 Bund Minze"
    ]
}
