--!strict
-- Every text of the game in six languages: French (the source), English, Spanish, German, Italian, Portuguese.
-- Each player sees and hears his Roblox language (LocalizationService.RobloxLocaleId); any other language gets English.
--
-- - On a player's machine: Lang.t("key", { name = value }) gives the text in his language.
-- - The server never sends a sentence: it sends Lang.L("key", args), a small coded message ("§key|{json args}"),
--   and each machine turns it into its own language with Lang.show(text). An argument may itself be a coded message
--   (a team name, a dribble's name...), translated too. Anything else (a player's name) is shown as it is.
-- - Several coded messages can be joined by new lines (the scorers board).
-- - Roblox's own automatic translation is switched off on the game's screens (client/Localize): it would translate
--   our translations again, and players' names.
local HttpService = game:GetService("HttpService")

local Lang = {}

Lang.LANGS = { "fr", "en", "es", "de", "it", "pt" }
local INDEX: { [string]: number } = { fr = 1, en = 2, es = 3, de = 4, it = 5, pt = 6 }
-- Text-to-speech voice for each language (Roblox's list of artificial voices)
Lang.VOICE = { fr = "401", en = "1", es = "101", de = "201", it = "301", pt = "1001" }

-- key = { fr, en, es, de, it, pt }
local S: { [string]: { string } } = {
	-- Teams, positions
	["team.1"] = { "Rouges", "Reds", "Rojos", "Roten", "Rossi", "Vermelhos" },
	["team.2"] = { "Bleus", "Blues", "Azules", "Blauen", "Blu", "Azuis" },
	["abbr.1"] = { "ROU", "RED", "ROJ", "ROT", "ROS", "VER" },
	["abbr.2"] = { "BLE", "BLU", "AZU", "BLA", "BLU", "AZU" },
	["role.GK"] = { "Gardien", "Goalkeeper", "Portero", "Torwart", "Portiere", "Goleiro" },
	["role.DF"] = { "Défenseur", "Defender", "Defensa", "Verteidiger", "Difensore", "Zagueiro" },
	["role.MF"] = { "Milieu", "Midfielder", "Centrocampista", "Mittelfeld", "Centrocampista", "Meio-campo" },
	["role.FW"] = { "Attaquant", "Forward", "Delantero", "Stürmer", "Attaccante", "Atacante" },

	-- Touch buttons
	["btn.shoot"] = { "Tir", "Shoot", "Tiro", "Schuss", "Tiro", "Chute" },
	["btn.pass"] = { "Passe", "Pass", "Pase", "Pass", "Passa", "Passe" },
	["btn.lob"] = { "Lob", "Lob", "Vaselina", "Heber", "Pallonetto", "Cavadinha" },
	["btn.sprint"] = { "Sprint", "Sprint", "Sprint", "Sprint", "Scatto", "Corrida" },
	["btn.tackle"] = { "Tacle", "Tackle", "Entrada", "Tackling", "Contrasto", "Desarme" },
	["btn.dribble"] = { "Dribble", "Dribble", "Regate", "Dribbling", "Dribbling", "Drible" },
	["btn.dive"] = { "Plonger", "Dive", "Estirada", "Hechten", "Tuffo", "Mergulho" },
	["btn.clear"] = { "Dégager", "Clear", "Despejar", "Klären", "Rinvio", "Afastar" },
	["btn.skip"] = { "Passer  »", "Skip  »", "Saltar  »", "Weiter  »", "Salta  »", "Pular  »" },

	-- Restarts
	["set.corner"] = { "Corner", "Corner", "Córner", "Ecke", "Calcio d’angolo", "Escanteio" },
	["set.freekick"] = { "Coup franc", "Free kick", "Tiro libre", "Freistoß", "Calcio di punizione", "Falta" },
	["set.penalty"] = { "Penalty", "Penalty", "Penalti", "Elfmeter", "Rigore", "Pênalti" },
	["set.throw"] = { "Touche", "Throw-in", "Saque de banda", "Einwurf", "Rimessa laterale", "Lateral" },
	["set.goalkick"] = { "Six mètres", "Goal kick", "Saque de puerta", "Abstoß", "Rinvio dal fondo", "Tiro de meta" },
	["set.kickoff"] = { "Coup d’envoi", "Kick-off", "Saque inicial", "Anstoß", "Calcio d’inizio", "Pontapé inicial" },
	["how.penalty"] = { "Vise avec le joystick, puis Tir", "Aim with the joystick, then Shoot", "Apunta con el joystick y luego Tiro",
		"Mit dem Joystick zielen, dann Schuss", "Mira con il joystick, poi Tiro", "Mire com o joystick e depois Chute" },
	["how.throw"] = { "Passe pour remettre en jeu", "Pass to throw the ball in", "Pase para sacar de banda", "Pass zum Einwerfen",
		"Passa per rimettere in gioco", "Passe para cobrar o lateral" },
	["how.other"] = { "Passe, Lob ou Tir pour jouer", "Pass, Lob or Shoot to play", "Pase, Vaselina o Tiro para jugar",
		"Pass, Heber oder Schuss zum Spielen", "Passa, Pallonetto o Tiro per giocare", "Passe, Cavadinha ou Chute para jogar" },
	["msg.yourturn"] = { "À toi : {kind}", "Your turn: {kind}", "Te toca: {kind}", "Du bist dran: {kind}", "Tocca a te: {kind}", "Sua vez: {kind}" },

	-- Big messages in the middle of the screen
	["say.shot"] = { "Tir !", "Shot!", "¡Disparo!", "Schuss!", "Tiro!", "Chute!" },
	["say.tackle"] = { "Tacle réussi !", "Great tackle!", "¡Buena entrada!", "Starkes Tackling!", "Bel contrasto!", "Belo desarme!" },
	["say.dribfail"] = { "{move} raté !", "{move} failed!", "¡{move} fallido!", "{move} misslungen!", "{move} fallito!", "{move} falhou!" },
	["say.dribperfect"] = { "{move} parfait !", "Perfect {move}!", "¡{move} perfecto!", "{move}: perfekt!", "{move} perfetto!", "{move} perfeito!" },
	["say.advantage"] = { "Avantage", "Advantage", "Ventaja", "Vorteil", "Vantaggio", "Vantagem" },
	["say.penalty"] = { "Penalty !", "Penalty!", "¡Penalti!", "Elfmeter!", "Rigore!", "Pênalti!" },
	["say.goal"] = { "BUT !", "GOAL!", "¡GOL!", "TOR!", "GOL!", "GOL!" },
	["say.post"] = { "Poteau !", "Off the post!", "¡Al poste!", "Pfosten!", "Palo!", "Na trave!" },
	["say.bar"] = { "Transversale !", "Off the bar!", "¡Al larguero!", "Latte!", "Traversa!", "No travessão!" },
	["say.offside"] = { "Hors-jeu", "Offside", "Fuera de juego", "Abseits", "Fuorigioco", "Impedimento" },
	["say.save"] = { "Arrêt !", "Save!", "¡Paradón!", "Parade!", "Parata!", "Defesa!" },
	["say.lost"] = { "Ballon perdu", "Ball lost", "Balón perdido", "Ball verloren", "Palla persa", "Bola perdida" },
	["say.half"] = { "Mi-temps", "Half-time", "Descanso", "Halbzeit", "Intervallo", "Intervalo" },
	["say.end"] = { "Fin du match", "Full time", "Final del partido", "Abpfiff", "Fine partita", "Fim de jogo" },
	["say.draw"] = { "Match nul", "Draw", "Empate", "Unentschieden", "Pareggio", "Empate" },
	["say.wins"] = { "Les {team} gagnent", "The {team} win", "Ganan los {team}", "Die {team} gewinnen", "Vincono i {team}", "Os {team} vencem" },
	["sub.goal"] = { "{team} · {who}", "{team} · {who}", "{team} · {who}", "{team} · {who}", "{team} · {who}", "{team} · {who}" },
	["sub.og"] = { "contre son camp", "own goal", "en propia puerta", "Eigentor", "autogol", "gol contra" },
	["sub.score"] = { "{a1} {s1} – {s2} {a2}", "{a1} {s1} – {s2} {a2}", "{a1} {s1} – {s2} {a2}", "{a1} {s1} – {s2} {a2}", "{a1} {s1} – {s2} {a2}", "{a1} {s1} – {s2} {a2}" },
	["sub.result"] = { "{res} · {s1} – {s2}", "{res} · {s1} – {s2}", "{res} · {s1} – {s2}", "{res} · {s1} – {s2}", "{res} · {s1} – {s2}", "{res} · {s1} – {s2}" },
	["sub.red"] = { "Carton rouge pour {a} (n°{n})", "Red card for {a} (no. {n})", "Tarjeta roja para {a} (n.º {n})", "Rote Karte für {a} (Nr. {n})",
		"Cartellino rosso per {a} (n. {n})", "Cartão vermelho para {a} (n.º {n})" },
	["sub.yellow"] = { "Carton jaune pour {a} (n°{n})", "Yellow card for {a} (no. {n})", "Tarjeta amarilla para {a} (n.º {n})", "Gelbe Karte für {a} (Nr. {n})",
		"Cartellino giallo per {a} (n. {n})", "Cartão amarelo para {a} (n.º {n})" },
	["sub.foul"] = { "Faute de {a} sur {b}", "Foul by {a} on {b}", "Falta de {a} sobre {b}", "Foul von {a} an {b}", "Fallo di {a} su {b}", "Falta de {a} em {b}" },
	["sub.offside"] = { "{a} était en position de hors-jeu", "{a} was offside", "{a} estaba en fuera de juego", "{a} stand im Abseits", "{a} era in fuorigioco", "{a} estava impedido" },
	["sub.tackledby"] = { "{a} te tacle", "{a} tackles you", "{a} te hace una entrada", "{a} tackelt dich", "{a} ti contrasta", "{a} te desarma" },
	["sub.tookball"] = { "{a} t’a pris le ballon", "{a} took the ball from you", "{a} te quitó el balón", "{a} hat dir den Ball abgenommen",
		"{a} ti ha rubato palla", "{a} roubou sua bola" },
	["sub.goalnow"] = { "But", "Goal", "Gol", "Tor", "Gol", "Gol" },
	["sub.loose"] = { "Ballon perdu", "Loose ball", "Balón suelto", "Ball verloren", "Palla persa", "Bola perdida" },

	-- Labels over the footballers' heads
	["lab.won"] = { "Ballon récupéré", "Ball won", "Balón recuperado", "Ball erobert", "Palla recuperata", "Bola recuperada" },
	["lab.noone"] = { "Personne à tacler", "Nobody to tackle", "Nadie a quien entrar", "Niemand zum Tacklen", "Nessuno da contrastare", "Ninguém para desarmar" },
	["lab.far"] = { "Trop loin", "Too far", "Demasiado lejos", "Zu weit", "Troppo lontano", "Longe demais" },
	["lab.tacklemiss"] = { "Tacle raté", "Missed tackle", "Entrada fallida", "Tackling verfehlt", "Contrasto mancato", "Desarme falhado" },
	["lab.tackle"] = { "Tacle !", "Tackle!", "¡Entrada!", "Tackling!", "Contrasto!", "Desarme!" },
	["lab.drib"] = { "{move} {pct} % : {res}", "{move} {pct} %: {res}", "{move} {pct} %: {res}", "{move} {pct} %: {res}", "{move} {pct} %: {res}", "{move} {pct} %: {res}" },
	["lab.dribstart"] = { "{move} {stars} {pct} %", "{move} {stars} {pct} %", "{move} {stars} {pct} %", "{move} {stars} {pct} %", "{move} {stars} {pct} %", "{move} {stars} {pct} %" },
	["lab.red"] = { "Carton rouge", "Red card", "Tarjeta roja", "Rote Karte", "Cartellino rosso", "Cartão vermelho" },
	["lab.yellow"] = { "Carton jaune", "Yellow card", "Tarjeta amarilla", "Gelbe Karte", "Cartellino giallo", "Cartão amarelo" },
	["lab.foul"] = { "Faute !", "Foul!", "¡Falta!", "Foul!", "Fallo!", "Falta!" },
	["lab.advantage"] = { "Avantage !", "Advantage!", "¡Ventaja!", "Vorteil!", "Vantaggio!", "Vantagem!" },
	["lab.offside"] = { "Hors-jeu", "Offside", "Fuera de juego", "Abseits", "Fuorigioco", "Impedimento" },
	["lab.beaten"] = { "Battu !", "Beaten!", "¡Batido!", "Geschlagen!", "Battuto!", "Batido!" },
	["lab.notyet"] = { "Pas encore…", "Not yet…", "Todavía no…", "Noch nicht…", "Non ancora…", "Ainda não…" },
	["res.0"] = { "Raté", "Failed", "Fallido", "Misslungen", "Fallito", "Falhou" },
	["res.1"] = { "À moitié", "Half", "A medias", "Halb", "A metà", "Pela metade" },
	["res.2"] = { "Réussi", "Success", "Logrado", "Gelungen", "Riuscito", "Certo" },
	["res.3"] = { "Parfait", "Perfect", "Perfecto", "Perfekt", "Perfetto", "Perfeito" },

	-- Commentary (also spoken)
	["c.seeks"] = { "{a} cherche {b}", "{a} looks for {b}", "{a} busca a {b}", "{a} sucht {b}", "{a} cerca {b}", "{a} procura {b}" },
	["c.pass"] = { "Passe de {a} pour {b}", "{a} passes to {b}", "Pase de {a} para {b}", "Pass von {a} auf {b}", "Passaggio di {a} per {b}", "Passe de {a} para {b}" },
	["c.shot"] = { "Frappe de {a} !", "{a} shoots!", "¡Disparo de {a}!", "Schuss von {a}!", "Tiro di {a}!", "Chute de {a}!" },
	["c.tackle"] = { "Tacle de {a}, il récupère le ballon.", "Tackle by {a}, he wins the ball.", "Entrada de {a}, recupera el balón.",
		"Tackling von {a}, er erobert den Ball.", "Contrasto di {a}, recupera il pallone.", "Desarme de {a}, ele recupera a bola." },
	["c.dribperfect"] = { "{move} parfait de {a} !", "Perfect {move} by {a}!", "¡{move} perfecto de {a}!", "{move} von {a}: perfekt!",
		"{move} perfetto di {a}!", "{move} perfeito de {a}!" },
	["c.dribnice"] = { "Joli geste de {a} : {move}.", "Nice skill from {a}: {move}.", "Bonito gesto de {a}: {move}.", "Schöne Aktion von {a}: {move}.",
		"Bel gesto di {a}: {move}.", "Bela jogada de {a}: {move}." },
	["c.setpiece"] = { "{kind} pour les {team}, {a} s’en charge.", "{kind} for the {team}, {a} takes it.", "{kind} para los {team}, lo lanza {a}.",
		"{kind} für die {team}, {a} tritt an.", "{kind} per i {team}, batte {a}.", "{kind} para os {team}, {a} vai cobrar." },
	["c.red"] = { "Carton rouge ! {a} est expulsé.", "Red card! {a} is sent off.", "¡Tarjeta roja! {a} es expulsado.", "Rote Karte! {a} fliegt vom Platz.",
		"Cartellino rosso! {a} è espulso.", "Cartão vermelho! {a} é expulso." },
	["c.yellow"] = { "Carton jaune pour {a}.", "Yellow card for {a}.", "Tarjeta amarilla para {a}.", "Gelbe Karte für {a}.", "Cartellino giallo per {a}.", "Cartão amarelo para {a}." },
	["c.foul"] = { "Faute de {a} sur {b}.", "Foul by {a} on {b}.", "Falta de {a} sobre {b}.", "Foul von {a} an {b}.", "Fallo di {a} su {b}.", "Falta de {a} em {b}." },
	["c.kickoff"] = { "Coup d’envoi pour les {team} !", "Kick-off for the {team}!", "¡Saque inicial para los {team}!", "Anstoß für die {team}!",
		"Calcio d’inizio per i {team}!", "Pontapé inicial para os {team}!" },
	["c.goal"] = { "BUT de {a} pour les {team} !", "GOAL by {a} for the {team}!", "¡GOL de {a} para los {team}!", "TOR von {a} für die {team}!",
		"GOL di {a} per i {team}!", "GOL de {a} para os {team}!" },
	["c.og"] = { "But contre son camp ! Cadeau pour les {team}.", "Own goal! A gift for the {team}.", "¡Gol en propia puerta! Regalo para los {team}.",
		"Eigentor! Ein Geschenk für die {team}.", "Autogol! Un regalo per i {team}.", "Gol contra! Presente para os {team}." },
	["c.offside"] = { "Hors-jeu de {a}, le drapeau se lève.", "{a} is offside, up goes the flag.", "Fuera de juego de {a}, se levanta la bandera.",
		"{a} im Abseits, die Fahne geht hoch.", "Fuorigioco di {a}, si alza la bandierina.", "Impedimento de {a}, a bandeira sobe." },
	["c.save"] = { "Arrêt de {a} !", "Great save by {a}!", "¡Parada de {a}!", "Parade von {a}!", "Parata di {a}!", "Defesa de {a}!" },
	["c.enters"] = { "{a} entre sur le terrain avec les {team} !", "{a} joins the {team} on the pitch!", "¡{a} entra al campo con los {team}!",
		"{a} läuft für die {team} auf!", "{a} entra in campo con i {team}!", "{a} entra em campo com os {team}!" },

	-- Joining, idle, VIP corner
	["join.ok"] = { "C’est parti !", "Let’s go!", "¡Vamos!", "Los geht’s!", "Si parte!", "Vamos lá!" },
	["join.already"] = { "Tu es déjà sur le terrain", "You are already on the pitch", "Ya estás en el campo", "Du bist schon auf dem Platz",
		"Sei già in campo", "Você já está em campo" },
	["join.noslot"] = { "Cette place n’existe pas", "This position does not exist", "Este puesto no existe", "Diese Position gibt es nicht",
		"Questo posto non esiste", "Essa posição não existe" },
	["join.taken"] = { "Place déjà prise", "Position already taken", "Puesto ocupado", "Position schon vergeben", "Posto già preso", "Posição já ocupada" },
	["join.invalid"] = { "Choix invalide", "Invalid choice", "Elección no válida", "Ungültige Wahl", "Scelta non valida", "Escolha inválida" },
	["idle.title"] = { "Tu es inactif", "You are idle", "Estás inactivo", "Du bist inaktiv", "Sei inattivo", "Você está parado" },
	["idle.sub"] = { "Bouge ou tu seras remplacé dans 20 s", "Move or you will be replaced in 20 s", "Muévete o serás reemplazado en 20 s",
		"Beweg dich, sonst wirst du in 20 s ersetzt", "Muoviti o sarai sostituito tra 20 s", "Mexa-se ou será substituído em 20 s" },
	["idle.kick"] = { "Inactif trop longtemps : un joueur de l’ordinateur a pris ta place. Reviens quand tu veux !",
		"Idle for too long: a computer player took your place. Come back whenever you like!",
		"Demasiado tiempo inactivo: un jugador del ordenador ocupó tu lugar. ¡Vuelve cuando quieras!",
		"Zu lange inaktiv: Ein Computerspieler hat deinen Platz übernommen. Komm wieder, wann du willst!",
		"Inattivo per troppo tempo: un giocatore del computer ha preso il tuo posto. Torna quando vuoi!",
		"Parado por muito tempo: um jogador do computador ficou com seu lugar. Volte quando quiser!" },
	["vip.title"] = { "Coin VIP", "VIP corner", "Rincón VIP", "VIP-Ecke", "Angolo VIP", "Cantinho VIP" },
	["vip.sub"] = { "Réservé aux VIP : le Pass VIP est à la boutique", "VIPs only: get the VIP Pass in the shop", "Solo para VIP: el Pase VIP está en la tienda",
		"Nur für VIPs: den VIP-Pass gibt es im Shop", "Riservato ai VIP: il Pass VIP è nel negozio", "Só para VIP: o Passe VIP está na loja" },

	-- Locker room
	["lobby.title"] = { "Choisis ton équipe et ton poste", "Pick your team and your position", "Elige tu equipo y tu puesto", "Wähle dein Team und deine Position",
		"Scegli la squadra e il ruolo", "Escolha seu time e sua posição" },
	["lobby.players1"] = { "{team}  ·  {n} joueur", "{team}  ·  {n} player", "{team}  ·  {n} jugador", "{team}  ·  {n} Spieler", "{team}  ·  {n} giocatore", "{team}  ·  {n} jogador" },
	["lobby.players"] = { "{team}  ·  {n} joueurs", "{team}  ·  {n} players", "{team}  ·  {n} jugadores", "{team}  ·  {n} Spieler", "{team}  ·  {n} giocatori", "{team}  ·  {n} jogadores" },
	["lobby.free"] = { "libre  »", "free  »", "libre  »", "frei  »", "libero  »", "livre  »" },
	["lobby.going"] = { "On t’envoie sur le terrain…", "Sending you onto the pitch…", "Te llevamos al campo…", "Ab auf den Platz…", "Ti mandiamo in campo…", "Levando você para o campo…" },
	["lobby.hint"] = { "Touche une place libre pour entrer sur le terrain. Les robots jouent les autres.",
		"Tap a free position to go onto the pitch. Robots play the others.",
		"Toca un puesto libre para entrar al campo. Los robots juegan los demás.",
		"Tippe auf eine freie Position, um aufs Feld zu gehen. Roboter spielen die anderen.",
		"Tocca un posto libero per entrare in campo. I robot giocano gli altri.",
		"Toque numa posição livre para entrar em campo. Os robôs jogam as outras." },
	["lobby.back"] = { "↩ Vestiaire", "↩ Locker room", "↩ Vestuario", "↩ Kabine", "↩ Spogliatoio", "↩ Vestiário" },
	["lobby.sign"] = { "MATCH ▼  choisis ton équipe", "MATCH ▼  pick your team", "PARTIDO ▼  elige tu equipo", "SPIEL ▼  wähle dein Team",
		"PARTITA ▼  scegli la squadra", "PARTIDA ▼  escolha seu time" },
	["lobby.shop"] = { "🛒 BOUTIQUE", "🛒 SHOP", "🛒 TIENDA", "🛒 SHOP", "🛒 NEGOZIO", "🛒 LOJA" },
	["board.title"] = { "⚽ MEILLEURS BUTEURS", "⚽ TOP SCORERS", "⚽ MÁXIMOS GOLEADORES", "⚽ TORSCHÜTZEN", "⚽ CAPOCANNONIERI", "⚽ ARTILHEIROS" },
	["board.none"] = { "Pas encore de but.", "No goals yet.", "Aún no hay goles.", "Noch keine Tore.", "Ancora nessun gol.", "Ainda sem gols." },
	["board.row1"] = { "{i}.  {a}  —  {n} but", "{i}.  {a}  —  {n} goal", "{i}.  {a}  —  {n} gol", "{i}.  {a}  —  {n} Tor", "{i}.  {a}  —  {n} gol", "{i}.  {a}  —  {n} gol" },
	["board.row"] = { "{i}.  {a}  —  {n} buts", "{i}.  {a}  —  {n} goals", "{i}.  {a}  —  {n} goles", "{i}.  {a}  —  {n} Tore", "{i}.  {a}  —  {n} gol", "{i}.  {a}  —  {n} gols" },

	-- On-screen graphics
	["hud.half1"] = { "1re mi-temps", "1st half", "1.ª parte", "1. Halbzeit", "1° tempo", "1º tempo" },
	["hud.half2"] = { "2e mi-temps", "2nd half", "2.ª parte", "2. Halbzeit", "2° tempo", "2º tempo" },
	["hud.ht"] = { "MT", "HT", "DES", "HZ", "INT", "INT" },
	["hud.over"] = { "terminé", "full time", "final", "Ende", "finita", "fim" },
	["hud.youplay"] = { "Tu joues pour les {team}", "You play for the {team}", "Juegas con los {team}", "Du spielst für die {team}", "Giochi per i {team}", "Você joga pelos {team}" },
	["hud.spectator"] = { "Spectateur", "Spectator", "Espectador", "Zuschauer", "Spettatore", "Espectador" },
	["hud.shot"] = { "Tir", "Shot", "Tiro", "Schuss", "Tiro", "Chute" },
	["hud.shotstrong"] = { "Tir · trop fort, risque au-dessus", "Shot · too hard, may go over", "Tiro · demasiado fuerte, puede irse alto",
		"Schuss · zu fest, geht vielleicht drüber", "Tiro · troppo forte, rischia di andare alto", "Chute · forte demais, pode ir por cima" },
	["hud.lob"] = { "Lob", "Lob", "Vaselina", "Heber", "Pallonetto", "Cavadinha" },
	["keys.1"] = { "ZQSD / WASD  Courir", "WASD  Run", "WASD  Correr", "WASD  Laufen", "WASD  Correre", "WASD  Correr" },
	["keys.2"] = { "J  Passe", "J  Pass", "J  Pase", "J  Pass", "J  Passa", "J  Passe" },
	["keys.3"] = { "K  Tir (maintenir = puissance)", "K  Shoot (hold = power)", "K  Tiro (mantener = potencia)", "K  Schuss (halten = Kraft)",
		"K  Tiro (tieni premuto = potenza)", "K  Chute (segurar = força)" },
	["keys.4"] = { "I  Lob (maintenir = loin et haut)", "I  Lob (hold = long and high)", "I  Vaselina (mantener = lejos y alto)", "I  Heber (halten = weit und hoch)",
		"I  Pallonetto (tieni premuto = lungo e alto)", "I  Cavadinha (segurar = longe e alto)" },
	["keys.5"] = { "L  Passe en profondeur", "L  Through ball", "L  Pase al hueco", "L  Steilpass", "L  Passaggio in profondità", "L  Passe em profundidade" },
	["keys.6"] = { "E  Tacle · Maj  Sprint", "E  Tackle · Shift  Sprint", "E  Entrada · Mayús  Sprint", "E  Tackling · Umschalt  Sprint",
		"E  Contrasto · Maiusc  Scatto", "E  Desarme · Shift  Corrida" },
	["keys.7"] = { "Espace  Saut (tête) · C  Caméra TV", "Space  Jump (header) · C  TV camera", "Espacio  Salto (cabezazo) · C  Cámara TV",
		"Leertaste  Sprung (Kopfball) · C  TV-Kamera", "Spazio  Salto (colpo di testa) · C  Telecamera TV", "Espaço  Pulo (cabeceio) · C  Câmera de TV" },
	["intro.ball"] = { "BALLON DU MATCH", "MATCH BALL", "BALÓN DEL PARTIDO", "SPIELBALL", "PALLONE DELLA PARTITA", "BOLA DA PARTIDA" },
	["ball.classique"] = { "Classique", "Classic", "Clásico", "Klassisch", "Classico", "Clássica" },
	["ball.etoiles"] = { "Étoiles", "Stars", "Estrellas", "Sterne", "Stelle", "Estrelas" },
	["replay.tag"] = { "● RALENTI", "● REPLAY", "● REPETICIÓN", "● ZEITLUPE", "● REPLAY", "● REPLAY" },

	-- End of the match
	["stats.title"] = { "FIN DU MATCH", "FULL TIME", "FINAL DEL PARTIDO", "ABPFIFF", "FINE PARTITA", "FIM DE JOGO" },
	["stats.poss"] = { "Possession", "Possession", "Posesión", "Ballbesitz", "Possesso palla", "Posse de bola" },
	["stats.shots"] = { "Tirs", "Shots", "Tiros", "Schüsse", "Tiri", "Chutes" },
	["stats.passes"] = { "Passes réussies", "Completed passes", "Pases completados", "Angekommene Pässe", "Passaggi riusciti", "Passes certos" },
	["stats.tackles"] = { "Tacles gagnés", "Tackles won", "Entradas ganadas", "Gewonnene Tacklings", "Contrasti vinti", "Desarmes certos" },
	["stats.fouls"] = { "Fautes", "Fouls", "Faltas", "Fouls", "Falli", "Faltas" },
	["stats.cards"] = { "Cartons", "Cards", "Tarjetas", "Karten", "Cartellini", "Cartões" },
	["stats.offsides"] = { "Hors-jeu", "Offsides", "Fueras de juego", "Abseits", "Fuorigioco", "Impedimentos" },
	["stats.motm"] = { "★ Homme du match : {a} ({abbr}) · {g} but(s), {p} passes, {t} tacles", "★ Player of the match: {a} ({abbr}) · {g} goal(s), {p} passes, {t} tackles",
		"★ Jugador del partido: {a} ({abbr}) · {g} gol(es), {p} pases, {t} entradas", "★ Spieler des Spiels: {a} ({abbr}) · {g} Tor(e), {p} Pässe, {t} Tacklings",
		"★ Migliore in campo: {a} ({abbr}) · {g} gol, {p} passaggi, {t} contrasti", "★ Craque da partida: {a} ({abbr}) · {g} gol(s), {p} passes, {t} desarmes" },

	-- Shop
	["shop.title"] = { "🛒 Boutique FC27", "🛒 FC27 Shop", "🛒 Tienda FC27", "🛒 FC27-Shop", "🛒 Negozio FC27", "🛒 Loja FC27" },
	["shop.open"] = { "🛒 Boutique", "🛒 Shop", "🛒 Tienda", "🛒 Shop", "🛒 Negozio", "🛒 Loja" },
	["shop.creator"] = { "CRÉATEUR : tout est offert", "CREATOR: everything is free", "CREADOR: todo es gratis", "ERSTELLER: alles gratis", "CREATORE: tutto gratis", "CRIADOR: tudo grátis" },
	["shop.note"] = { "Tout est cosmétique : rien ne rend plus fort, tout se voit sur le terrain.", "Everything is cosmetic: nothing makes you stronger, everyone sees it on the pitch.",
		"Todo es estético: nada te hace más fuerte, todos lo ven en el campo.", "Alles nur Optik: Nichts macht stärker, alle sehen es auf dem Platz.",
		"Tutto è estetico: niente rende più forti, tutti lo vedono in campo.", "Tudo é visual: nada deixa você mais forte, todos veem em campo." },
	["shop.error"] = { "Erreur, réessaie", "Error, try again", "Error, inténtalo de nuevo", "Fehler, versuch es nochmal", "Errore, riprova", "Erro, tente de novo" },
	["shop.paying"] = { "Paiement Roblox en cours…", "Roblox payment in progress…", "Pago de Roblox en curso…", "Roblox-Zahlung läuft…", "Pagamento Roblox in corso…", "Pagamento Roblox em andamento…" },
	["shop.coins"] = { "Pièces", "Coins", "Monedas", "Münzen", "Monete", "Moedas" },
	["shop.coinsinfo"] = { "Pour acheter les articles. Tu en gagnes aussi en jouant !", "To buy the items. You also earn them by playing!",
		"Para comprar los artículos. ¡También las ganas jugando!", "Zum Kaufen der Artikel. Du verdienst sie auch beim Spielen!",
		"Per comprare gli articoli. Le guadagni anche giocando!", "Para comprar os itens. Você também ganha jogando!" },
	["shop.gain"] = { "+{n} pièces · {why}", "+{n} coins · {why}", "+{n} monedas · {why}", "+{n} Münzen · {why}", "+{n} monete · {why}", "+{n} moedas · {why}" },
	["reason.goal"] = { "But", "Goal", "Gol", "Tor", "Gol", "Gol" },
	["reason.pass"] = { "Passe", "Pass", "Pase", "Pass", "Passaggio", "Passe" },
	["reason.tackle"] = { "Tacle", "Tackle", "Entrada", "Tackling", "Contrasto", "Desarme" },
	["reason.win"] = { "Victoire", "Win", "Victoria", "Sieg", "Vittoria", "Vitória" },
	["reason.draw"] = { "Match nul", "Draw", "Empate", "Unentschieden", "Pareggio", "Empate" },
	["shop.loading"] = { "Chargement…", "Loading…", "Cargando…", "Lädt…", "Caricamento…", "Carregando…" },
	["shop.unknown"] = { "Article inconnu", "Unknown item", "Artículo desconocido", "Unbekannter Artikel", "Articolo sconosciuto", "Item desconhecido" },
	["shop.have"] = { "Tu l’as déjà", "You already have it", "Ya lo tienes", "Du hast es schon", "Ce l’hai già", "Você já tem" },
	["shop.missing"] = { "Il te manque {n} pièces", "You need {n} more coins", "Te faltan {n} monedas", "Dir fehlen {n} Münzen", "Ti mancano {n} monete", "Faltam {n} moedas" },
	["shop.unlocked"] = { "{item} débloqué !", "{item} unlocked!", "¡{item} desbloqueado!", "{item} freigeschaltet!", "{item} sbloccato!", "{item} desbloqueado!" },
	["shop.gift"] = { "{item} : offert (créateur du jeu)", "{item}: free (game creator)", "{item}: gratis (creador del juego)", "{item}: gratis (Ersteller des Spiels)",
		"{item}: gratis (creatore del gioco)", "{item}: grátis (criador do jogo)" },
	["shop.soon"] = { "Bientôt disponible en Robux", "Coming soon for Robux", "Pronto disponible con Robux", "Bald für Robux erhältlich", "Presto disponibile in Robux", "Em breve por Robux" },
	["shop.packunknown"] = { "Pack inconnu", "Unknown pack", "Paquete desconocido", "Unbekanntes Paket", "Pacchetto sconosciuto", "Pacote desconhecido" },
	["shop.packgift"] = { "+{n} pièces : offertes (créateur du jeu)", "+{n} coins: free (game creator)", "+{n} monedas: gratis (creador del juego)",
		"+{n} Münzen: gratis (Ersteller des Spiels)", "+{n} monete: gratis (creatore del gioco)", "+{n} moedas: grátis (criador do jogo)" },
	["shop.packsoon"] = { "Bientôt disponible", "Coming soon", "Pronto disponible", "Bald erhältlich", "Presto disponibile", "Em breve" },
	["shop.notowned"] = { "Article non acheté", "Item not bought", "Artículo no comprado", "Artikel nicht gekauft", "Articolo non acquistato", "Item não comprado" },
	["shop.badchoice"] = { "Choix inconnu", "Unknown choice", "Elección desconocida", "Unbekannte Wahl", "Scelta sconosciuta", "Escolha desconhecida" },
	["shop.equipped"] = { "Équipé", "Equipped", "Equipado", "Ausgerüstet", "Equipaggiato", "Equipado" },
	["item.celebrations.name"] = { "Célébrations", "Celebrations", "Celebraciones", "Torjubel", "Esultanze", "Comemorações" },
	["item.celebrations.desc"] = { "Après chaque but, ton joueur fait sa fête : Siuu, danse, victoire ou bravo. Tout le stade la voit !",
		"After each goal, your player celebrates: Siuu, dance, victory or clap. The whole stadium sees it!",
		"Después de cada gol, tu jugador lo celebra: Siuu, baile, victoria o aplausos. ¡Todo el estadio lo ve!",
		"Nach jedem Tor jubelt dein Spieler: Siuu, Tanz, Sieg oder Applaus. Das ganze Stadion sieht es!",
		"Dopo ogni gol, il tuo giocatore esulta: Siuu, balletto, vittoria o applausi. Tutto lo stadio lo vede!",
		"Depois de cada gol, seu jogador comemora: Siuu, dança, vitória ou palmas. O estádio inteiro vê!" },
	["item.style.name"] = { "Crampons et maillots", "Boots and shirts", "Botas y camisetas", "Schuhe und Trikots", "Scarpe e maglie", "Chuteiras e camisas" },
	["item.style.desc"] = { "Des crampons de couleur et un maillot doré ou noir. Ta couleur d’équipe reste, pour qu’on te reconnaisse.",
		"Coloured boots and a gold or black shirt. Your team colour stays, so everyone knows who you are.",
		"Botas de colores y una camiseta dorada o negra. El color de tu equipo se queda, para que te reconozcan.",
		"Bunte Schuhe und ein goldenes oder schwarzes Trikot. Deine Teamfarbe bleibt, damit man dich erkennt.",
		"Scarpe colorate e una maglia d’oro o nera. Il colore della squadra resta, così ti riconoscono.",
		"Chuteiras coloridas e uma camisa dourada ou preta. A cor do seu time continua, para todos te reconhecerem." },
	["item.vip.name"] = { "Pass VIP", "VIP Pass", "Pase VIP", "VIP-Pass", "Pass VIP", "Passe VIP" },
	["item.vip.desc"] = { "Ton nom s’écrit en doré avec une étoile ★ au-dessus de ton joueur, et tu entres dans le coin VIP du vestiaire.",
		"Your name shows in gold with a star ★ above your player, and you can enter the VIP corner of the locker room.",
		"Tu nombre aparece en dorado con una estrella ★ sobre tu jugador, y entras en el rincón VIP del vestuario.",
		"Dein Name erscheint golden mit einem Stern ★ über deinem Spieler, und du darfst in die VIP-Ecke der Kabine.",
		"Il tuo nome appare in oro con una stella ★ sopra il giocatore, e puoi entrare nell’angolo VIP dello spogliatoio.",
		"Seu nome aparece dourado com uma estrela ★ acima do seu jogador, e você entra no cantinho VIP do vestiário." },
	["item.trail.name"] = { "Effet de tir", "Shot effect", "Efecto de tiro", "Schuss-Effekt", "Effetto tiro", "Efeito de chute" },
	["item.trail.desc"] = { "Quand tu tires, le ballon laisse une traînée derrière lui : feu, étoiles ou glace.",
		"When you shoot, the ball leaves a trail behind it: fire, stars or ice.",
		"Cuando disparas, el balón deja una estela: fuego, estrellas o hielo.",
		"Wenn du schießt, zieht der Ball eine Spur hinter sich her: Feuer, Sterne oder Eis.",
		"Quando tiri, il pallone lascia una scia: fuoco, stelle o ghiaccio.",
		"Quando você chuta, a bola deixa um rastro: fogo, estrelas ou gelo." },
	["choice.celebration.siuu"] = { "Siuu", "Siuu", "Siuu", "Siuu", "Siuu", "Siuu" },
	["choice.celebration.dance"] = { "Danse", "Dance", "Baile", "Tanz", "Balletto", "Dança" },
	["choice.celebration.victory"] = { "Victoire", "Victory", "Victoria", "Sieg", "Vittoria", "Vitória" },
	["choice.celebration.clap"] = { "Applaudir", "Clap", "Aplaudir", "Klatschen", "Applausi", "Palmas" },
	["choice.boots.gold"] = { "Dorés", "Gold", "Dorados", "Gold", "Oro", "Douradas" },
	["choice.boots.black"] = { "Noirs", "Black", "Negros", "Schwarz", "Nere", "Pretas" },
	["choice.boots.white"] = { "Blancs", "White", "Blancos", "Weiß", "Bianche", "Brancas" },
	["choice.boots.pink"] = { "Roses", "Pink", "Rosas", "Pink", "Rosa", "Rosa" },
	["choice.boots.cyan"] = { "Cyan", "Cyan", "Cian", "Cyan", "Ciano", "Ciano" },
	["choice.trail.fire"] = { "Feu", "Fire", "Fuego", "Feuer", "Fuoco", "Fogo" },
	["choice.trail.stars"] = { "Étoiles", "Stars", "Estrellas", "Sterne", "Stelle", "Estrelas" },
	["choice.trail.ice"] = { "Glace", "Ice", "Hielo", "Eis", "Ghiaccio", "Gelo" },
	["choice.kit.classic"] = { "Classique", "Classic", "Clásica", "Klassisch", "Classica", "Clássica" },
	["choice.kit.gold"] = { "Édition or", "Gold edition", "Edición oro", "Gold-Edition", "Edizione oro", "Edição ouro" },
	["choice.kit.dark"] = { "Édition noire", "Black edition", "Edición negra", "Schwarze Edition", "Edizione nera", "Edição preta" },

	-- Skill moves
	["drib.crochet"] = { "Crochet", "Cut", "Recorte", "Haken", "Finta a rientrare", "Corte" },
	["drib.corps"] = { "Feinte de corps", "Body feint", "Finta de cuerpo", "Körpertäuschung", "Finta di corpo", "Finta de corpo" },
	["drib.rateau"] = { "Râteau", "Drag back", "Arrastre", "Zurückziehen", "Trascinamento", "Puxada" },
	["drib.stopgo"] = { "Arrêt-départ", "Stop and go", "Parar y salir", "Stop and Go", "Stop and go", "Para e arranca" },
	["drib.fpasse"] = { "Feinte de passe", "Fake pass", "Amago de pase", "Passtäuschung", "Finta di passaggio", "Finta de passe" },
	["drib.passement"] = { "Passement de jambes", "Step-over", "Bicicleta", "Übersteiger", "Doppio passo", "Pedalada" },
	["drib.passinv"] = { "Passement inversé", "Reverse step-over", "Bicicleta inversa", "Umgekehrter Übersteiger", "Doppio passo inverso", "Pedalada invertida" },
	["drib.croqueta"] = { "La croqueta", "La croqueta", "La croqueta", "La Croqueta", "La croqueta", "La croqueta" },
	["drib.semelle"] = { "Roulé de semelle", "Sole roll", "Rueda con la suela", "Sohlenrolle", "Suola", "Rolinho de sola" },
	["drib.cruyff"] = { "Crochet Cruyff", "Cruyff turn", "Giro de Cruyff", "Cruyff-Drehung", "Finta di Cruyff", "Giro de Cruyff" },
	["drib.chop"] = { "Chop (Ronaldo)", "Chop (Ronaldo)", "Chop (Ronaldo)", "Chop (Ronaldo)", "Chop (Ronaldo)", "Chop (Ronaldo)" },
	["drib.frappe"] = { "Feinte de frappe", "Fake shot", "Amago de tiro", "Schusstäuschung", "Finta di tiro", "Finta de chute" },
	["drib.grandpont"] = { "Grand pont", "Knock and run", "Autopase", "Vorbeilegen", "Sombrero lungo", "Drible da vaca" },
	["drib.roulette"] = { "Roulette marseillaise", "Roulette", "Ruleta", "Marseille-Drehung", "Veronica", "Roleta" },
	["drib.doublepass"] = { "Double passement", "Double step-over", "Doble bicicleta", "Doppelter Übersteiger", "Doppio doppio passo", "Pedalada dupla" },
	["drib.berbatov"] = { "Pirouette Berbatov", "Berbatov spin", "Giro Berbatov", "Berbatov-Drehung", "Giravolta Berbatov", "Giro Berbatov" },
	["drib.talon"] = { "Talonnade", "Back heel", "Taconazo", "Hackentrick", "Colpo di tacco", "Calcanhar" },
	["drib.talontalon"] = { "Talon-talon", "Heel to heel", "Tacón-tacón", "Hacke-Hacke", "Tacco-tacco", "Calcanhar duplo" },
	["drib.petitpont"] = { "Petit pont", "Nutmeg", "Caño", "Tunnel", "Tunnel", "Caneta" },
	["drib.elastico"] = { "Elastico (Ronaldinho)", "Elastico (Ronaldinho)", "Elástica (Ronaldinho)", "Elastico (Ronaldinho)", "Elastico (Ronaldinho)", "Elástico (Ronaldinho)" },
	["drib.elainv"] = { "Elastico inversé", "Reverse elastico", "Elástica inversa", "Umgekehrter Elastico", "Elastico inverso", "Elástico invertido" },
	["drib.rabona"] = { "Feinte de rabona", "Rabona fake", "Amago de rabona", "Rabona-Täuschung", "Finta di rabona", "Finta de letra" },
	["drib.mcgeady"] = { "Spin McGeady", "McGeady spin", "Giro McGeady", "McGeady-Drehung", "Giravolta McGeady", "Giro McGeady" },
	["drib.okocha"] = { "Coup d’Okocha", "Okocha flick", "Truco de Okocha", "Okocha-Trick", "Colpo di Okocha", "Truque do Okocha" },
	["drib.bolasie"] = { "Flick Bolasie", "Bolasie flick", "Toque Bolasie", "Bolasie-Flick", "Tocco Bolasie", "Toque Bolasie" },
	["drib.sombrero"] = { "Sombrero", "Sombrero flick", "Sombrero", "Sombrero", "Sombrero", "Chapéu" },
	["drib.arcenciel"] = { "Arc-en-ciel (Neymar)", "Rainbow flick (Neymar)", "Lambretta (Neymar)", "Regenbogen (Neymar)", "Arcobaleno (Neymar)", "Lambreta (Neymar)" },
	["drib.hocus"] = { "Hocus-pocus", "Hocus pocus", "Hocus pocus", "Hokuspokus", "Hocus pocus", "Hocus pocus" },
	["drib.cuauhtemina"] = { "Cuauhtemiña", "Cuauhtemiña", "Cuauhtemiña", "Cuauhtemiña", "Cuauhtemiña", "Cuauhtemiña" },
	["drib.tornade"] = { "Tornade", "Tornado", "Tornado", "Tornado", "Tornado", "Tornado" },
	["drib.otarie"] = { "Dribble de l’otarie (Kerlon)", "Seal dribble (Kerlon)", "Regate de foca (Kerlon)", "Robben-Dribbling (Kerlon)", "Dribbling della foca (Kerlon)", "Drible da foca (Kerlon)" },
}
Lang.STRINGS = S

-- The player's language (on his machine), among the six; any other language gets English
function Lang.code(locale: string?): string
	local l = string.lower(string.sub(locale or "", 1, 2))
	return if INDEX[l] then l else "en"
end

local current = "fr"
pcall(function()
	if game:GetService("RunService"):IsClient() then
		current = Lang.code(game:GetService("LocalizationService").RobloxLocaleId)
	end
end)
function Lang.current(): string return current end

local show: (s: any, lang: string?) -> string

-- The text for a key, in a language (by default this player's), with its {arguments} filled in
function Lang.t(key: string, args: { [string]: any }?, lang: string?): string
	local row = S[key]
	local text = if row then (row[INDEX[lang or current] or 2] or row[1]) else key
	if args then
		text = string.gsub(text, "{(%w+)}", function(k: string)
			local v = (args :: any)[k]
			if v == nil then return "{" .. k .. "}" end
			return show(v, lang)
		end)
	end
	return text
end

-- A coded message, sent by the server (or kept) instead of a sentence
function Lang.L(key: string, args: { [string]: any }?): string
	if args then return "§" .. key .. "|" .. HttpService:JSONEncode(args) end
	return "§" .. key
end

-- Any text: a coded message (or several, one per line) in this player's language; anything else as it is
show = function(s: any, lang: string?): string
	if type(s) ~= "string" then return tostring(s) end
	if string.sub(s, 1, 2) ~= "§" then return s end -- "§" is two bytes in UTF-8
	if string.find(s, "\n", 1, true) then
		local lines = {}
		for line in string.gmatch(s, "[^\n]+") do table.insert(lines, show(line, lang)) end
		return table.concat(lines, "\n")
	end
	local body = string.sub(s, 3)
	local bar = string.find(body, "|", 1, true)
	if not bar then return Lang.t(body, nil, lang) end
	local ok, args = pcall(function() return HttpService:JSONDecode(string.sub(body, bar + 1)) end)
	return Lang.t(string.sub(body, 1, bar - 1), if ok and type(args) == "table" then args else nil, lang)
end
Lang.show = show

-- Team name (translated), for a team number
function Lang.team(t: number): string return "§team." .. tostring(t) end
function Lang.abbr(t: number): string return "§abbr." .. tostring(t) end

return Lang
