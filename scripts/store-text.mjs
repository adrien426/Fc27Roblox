// The texts of the game's Roblox page and of its shop items (game passes, coin packs), in the six languages of the
// game (French is the source; the others are sent as translations). Used by create-shop.mjs and game-page.mjs.
export const LANGS = ['fr', 'en', 'es', 'de', 'it', 'pt'];

const COSMETIC = {
  fr: 'Pour le style seulement : ça ne rend pas ton joueur plus fort.',
  en: 'Just for style: it does not make your player stronger.',
  es: 'Solo por estilo: no hace más fuerte a tu jugador.',
  de: 'Nur für den Look: Dein Spieler wird dadurch nicht stärker.',
  it: 'Solo per stile: non rende il tuo giocatore più forte.',
  pt: 'Só para estilo: não deixa seu jogador mais forte.',
};
const PICK = {
  fr: 'Tu choisis dans la boutique du vestiaire.',
  en: 'You choose it in the locker room shop.',
  es: 'Lo eliges en la tienda del vestuario.',
  de: 'Du wählst ihn im Shop in der Kabine.',
  it: 'Lo scegli nel negozio dello spogliatoio.',
  pt: 'Você escolhe na loja do vestiário.',
};
const COINS = {
  fr: n => `${n} pièces FC27 pour acheter des articles de la boutique du vestiaire. Tu gagnes aussi des pièces en jouant : buts, passes, tacles et victoires.`,
  en: n => `${n} FC27 coins to buy items in the locker room shop. You also earn coins by playing: goals, passes, tackles and wins.`,
  es: n => `${n} monedas FC27 para comprar artículos en la tienda del vestuario. También ganas monedas jugando: goles, pases, entradas y victorias.`,
  de: n => `${n} FC27-Münzen für Artikel im Shop in der Kabine. Münzen verdienst du auch beim Spielen: Tore, Pässe, Tacklings und Siege.`,
  it: n => `${n} monete FC27 per comprare articoli nel negozio dello spogliatoio. Guadagni monete anche giocando: gol, passaggi, contrasti e vittorie.`,
  pt: n => `${n} moedas FC27 para comprar itens na loja do vestiário. Você também ganha moedas jogando: gols, passes, desarmes e vitórias.`,
};
const COIN_NAME = { fr: 'pièces', en: 'coins', es: 'monedas', de: 'Münzen', it: 'monete', pt: 'moedas' };

// id -> { lang: { name, description } }
export const PASS_TEXT = {
  celebrations: {
    fr: ['FC27 Célébrations', 'Après chaque but, ton joueur fait sa fête : Siuu, danse, victoire ou bravo. Tout le stade la voit !'],
    en: ['FC27 Celebrations', 'After each goal, your player celebrates: Siuu, dance, victory or clap. The whole stadium sees it!'],
    es: ['FC27 Celebraciones', 'Después de cada gol, tu jugador lo celebra: Siuu, baile, victoria o aplausos. ¡Todo el estadio lo ve!'],
    de: ['FC27 Torjubel', 'Nach jedem Tor jubelt dein Spieler: Siuu, Tanz, Sieg oder Applaus. Das ganze Stadion sieht es!'],
    it: ['FC27 Esultanze', 'Dopo ogni gol, il tuo giocatore esulta: Siuu, balletto, vittoria o applausi. Tutto lo stadio lo vede!'],
    pt: ['FC27 Comemorações', 'Depois de cada gol, seu jogador comemora: Siuu, dança, vitória ou palmas. O estádio inteiro vê!'],
  },
  style: {
    fr: ['FC27 Crampons et maillots', 'Des crampons de couleur (dorés, noirs, blancs, roses ou cyan) et un maillot édition or ou noire. Ta couleur d’équipe reste, pour qu’on te reconnaisse.'],
    en: ['FC27 Boots and shirts', 'Coloured boots (gold, black, white, pink or cyan) and a gold or black edition shirt. Your team colour stays, so everyone knows who you are.'],
    es: ['FC27 Botas y camisetas', 'Botas de colores (doradas, negras, blancas, rosas o cian) y una camiseta edición oro o negra. El color de tu equipo se queda, para que te reconozcan.'],
    de: ['FC27 Schuhe und Trikots', 'Bunte Schuhe (gold, schwarz, weiß, pink oder cyan) und ein Trikot in Gold- oder Schwarz-Edition. Deine Teamfarbe bleibt, damit man dich erkennt.'],
    it: ['FC27 Scarpe e maglie', 'Scarpe colorate (oro, nere, bianche, rosa o ciano) e una maglia edizione oro o nera. Il colore della squadra resta, così ti riconoscono.'],
    pt: ['FC27 Chuteiras e camisas', 'Chuteiras coloridas (douradas, pretas, brancas, rosa ou ciano) e uma camisa edição ouro ou preta. A cor do seu time continua, para todos te reconhecerem.'],
  },
  vip: {
    fr: ['FC27 Pass VIP', 'Ton nom s’écrit en doré avec une étoile ★ au-dessus de ton joueur, et tu entres dans le coin VIP du vestiaire.'],
    en: ['FC27 VIP Pass', 'Your name shows in gold with a star ★ above your player, and you can enter the VIP corner of the locker room.'],
    es: ['FC27 Pase VIP', 'Tu nombre aparece en dorado con una estrella ★ sobre tu jugador, y entras en el rincón VIP del vestuario.'],
    de: ['FC27 VIP-Pass', 'Dein Name erscheint golden mit einem Stern ★ über deinem Spieler, und du darfst in die VIP-Ecke der Kabine.'],
    it: ['FC27 Pass VIP', 'Il tuo nome appare in oro con una stella ★ sopra il giocatore, e puoi entrare nell’angolo VIP dello spogliatoio.'],
    pt: ['FC27 Passe VIP', 'Seu nome aparece dourado com uma estrela ★ acima do seu jogador, e você entra no cantinho VIP do vestiário.'],
  },
  trail: {
    fr: ['FC27 Effet de tir', 'Quand tu tires, le ballon laisse une traînée derrière lui : feu, étoiles ou glace.'],
    en: ['FC27 Shot effect', 'When you shoot, the ball leaves a trail behind it: fire, stars or ice.'],
    es: ['FC27 Efecto de tiro', 'Cuando disparas, el balón deja una estela: fuego, estrellas o hielo.'],
    de: ['FC27 Schuss-Effekt', 'Wenn du schießt, zieht der Ball eine Spur hinter sich her: Feuer, Sterne oder Eis.'],
    it: ['FC27 Effetto tiro', 'Quando tiri, il pallone lascia una scia: fuoco, stelle o ghiaccio.'],
    pt: ['FC27 Efeito de chute', 'Quando você chuta, a bola deixa um rastro: fogo, estrelas ou gelo.'],
  },
};
const PICKS = new Set(['celebrations', 'trail']);

// The text of a pass in a language: { name, description }
export function passText(id, lang) {
  const [name, desc] = PASS_TEXT[id][lang];
  return { name, description: `${desc} ${PICKS.has(id) ? PICK[lang] + ' ' : ''}${COSMETIC[lang]}` };
}
export function packText(coins, lang) {
  return { name: `FC27 ${coins} ${COIN_NAME[lang]}`, description: COINS[lang](coins) };
}

export const GAME_DESCRIPTION = {
  fr: `⚽ FC27 : le foot à 11 contre 11 !

Joue avec tes amis dans un vrai stade. Choisis ton équipe (Rouges ou Bleus) et ton poste dans le vestiaire : attaquant, milieu, défenseur ou gardien. Les places libres sont prises par des robots, donc tu peux jouer même tout seul.

🎮 Comment jouer
• Cours avec le joystick
• Passe, Lob et Tir pour jouer le ballon
• Tacle pour récupérer le ballon
• Dribble pour faire des gestes techniques
• Gardien : Plonger pour arrêter les tirs

🏆 Dans le jeu
• Hors-jeu, fautes, cartons, penaltys, corners et touches
• Ralenti après chaque but
• Statistiques à la fin du match et classement des meilleurs buteurs
• Un commentateur qui parle ta langue

🪙 Gagne des pièces en jouant (buts, passes, tacles, victoires) et débloque des célébrations, des crampons de couleur, des maillots spéciaux et des effets de tir. Tout est pour le style : rien ne rend ton joueur plus fort.`,
  en: `⚽ FC27: 11-a-side football!

Play with your friends in a real stadium. Pick your team (Reds or Blues) and your position in the locker room: forward, midfielder, defender or goalkeeper. Free positions are played by robots, so you can even play on your own.

🎮 How to play
• Run with the joystick
• Pass, Lob and Shoot to play the ball
• Tackle to win the ball back
• Dribble to do skill moves
• Goalkeeper: Dive to stop shots

🏆 In the game
• Offside, fouls, cards, penalties, corners and throw-ins
• Replay after every goal
• Match statistics at full time and a top scorers board
• A commentator who speaks your language

🪙 Earn coins by playing (goals, passes, tackles, wins) and unlock celebrations, coloured boots, special shirts and shot effects. It is all just for style: nothing makes your player stronger.`,
  es: `⚽ FC27: ¡fútbol 11 contra 11!

Juega con tus amigos en un estadio de verdad. Elige tu equipo (Rojos o Azules) y tu puesto en el vestuario: delantero, centrocampista, defensa o portero. Los puestos libres los juegan robots, así que puedes jugar incluso solo.

🎮 Cómo jugar
• Corre con el joystick
• Pase, Vaselina y Tiro para jugar el balón
• Entrada para recuperar el balón
• Regate para hacer filigranas
• Portero: Estirada para parar los tiros

🏆 En el juego
• Fuera de juego, faltas, tarjetas, penaltis, córners y saques de banda
• Repetición después de cada gol
• Estadísticas al final del partido y tabla de máximos goleadores
• Un comentarista que habla tu idioma

🪙 Gana monedas jugando (goles, pases, entradas, victorias) y desbloquea celebraciones, botas de colores, camisetas especiales y efectos de tiro. Todo es solo estético: nada hace más fuerte a tu jugador.`,
  de: `⚽ FC27: Fußball elf gegen elf!

Spiel mit deinen Freunden in einem echten Stadion. Wähle in der Kabine dein Team (Rote oder Blaue) und deine Position: Stürmer, Mittelfeld, Verteidiger oder Torwart. Freie Positionen spielen Roboter, du kannst also auch allein spielen.

🎮 So wird gespielt
• Laufen mit dem Joystick
• Pass, Heber und Schuss, um den Ball zu spielen
• Tackling, um den Ball zu erobern
• Dribbling für Tricks
• Torwart: Hechten, um Schüsse zu halten

🏆 Im Spiel
• Abseits, Fouls, Karten, Elfmeter, Ecken und Einwürfe
• Zeitlupe nach jedem Tor
• Statistiken nach dem Abpfiff und eine Torschützenliste
• Ein Kommentator, der deine Sprache spricht

🪙 Verdiene Münzen beim Spielen (Tore, Pässe, Tacklings, Siege) und schalte Torjubel, bunte Schuhe, besondere Trikots und Schuss-Effekte frei. Alles nur für den Look: Nichts macht deinen Spieler stärker.`,
  it: `⚽ FC27: calcio a 11 contro 11!

Gioca con i tuoi amici in un vero stadio. Scegli la squadra (Rossi o Blu) e il ruolo nello spogliatoio: attaccante, centrocampista, difensore o portiere. I posti liberi li giocano i robot, quindi puoi giocare anche da solo.

🎮 Come si gioca
• Corri con il joystick
• Passa, Pallonetto e Tiro per giocare il pallone
• Contrasto per recuperare il pallone
• Dribbling per fare giocate
• Portiere: Tuffo per parare i tiri

🏆 Nel gioco
• Fuorigioco, falli, cartellini, rigori, calci d’angolo e rimesse
• Replay dopo ogni gol
• Statistiche a fine partita e classifica dei capocannonieri
• Un telecronista che parla la tua lingua

🪙 Guadagna monete giocando (gol, passaggi, contrasti, vittorie) e sblocca esultanze, scarpe colorate, maglie speciali ed effetti di tiro. È tutto solo stile: niente rende il tuo giocatore più forte.`,
  pt: `⚽ FC27: futebol 11 contra 11!

Jogue com seus amigos num estádio de verdade. Escolha seu time (Vermelhos ou Azuis) e sua posição no vestiário: atacante, meio-campo, zagueiro ou goleiro. As posições livres são jogadas por robôs, então dá para jogar até sozinho.

🎮 Como jogar
• Corra com o joystick
• Passe, Cavadinha e Chute para jogar a bola
• Desarme para recuperar a bola
• Drible para fazer jogadas
• Goleiro: Mergulho para defender os chutes

🏆 No jogo
• Impedimento, faltas, cartões, pênaltis, escanteios e laterais
• Replay depois de cada gol
• Estatísticas no fim da partida e ranking de artilheiros
• Um narrador que fala a sua língua

🪙 Ganhe moedas jogando (gols, passes, desarmes, vitórias) e desbloqueie comemorações, chuteiras coloridas, camisas especiais e efeitos de chute. É tudo só estilo: nada deixa seu jogador mais forte.`,
};

// The titles drawn on the thumbnails (scripts/art), per language
export const THUMB_TITLES = {
  fr: { t1: 'Foot à 11 contre 11 !', t2: 'BUUUT !', t3a: 'Célèbre tes buts !', t3b: 'Crampons, maillots, effets de tir' },
  en: { t1: '11-a-side football!', t2: 'GOOOAL!', t3a: 'Celebrate your goals!', t3b: 'Boots, shirts, shot effects' },
  es: { t1: '¡Fútbol 11 contra 11!', t2: '¡GOOOL!', t3a: '¡Celebra tus goles!', t3b: 'Botas, camisetas, efectos de tiro' },
  de: { t1: 'Fußball elf gegen elf!', t2: 'TOOOR!', t3a: 'Feier deine Tore!', t3b: 'Schuhe, Trikots, Schuss-Effekte' },
  it: { t1: 'Calcio a 11 contro 11!', t2: 'GOOOL!', t3a: 'Festeggia i tuoi gol!', t3b: 'Scarpe, maglie, effetti di tiro' },
  pt: { t1: 'Futebol 11 contra 11!', t2: 'GOOOL!', t3a: 'Comemore seus gols!', t3b: 'Chuteiras, camisas, efeitos de chute' },
};
