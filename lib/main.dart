import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:swipe_path_typer/swipe_path_typer.dart';

void main() {
  runApp(const MyApp());
}

enum GamePhase {
  starting,
  startSplit,
  splitting,
  splitWord,
  startMerging,
  merging,
  formedWord,
  gameOver,
  pauseGame
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  // The duration a player has to find a word (starts with the new split, or the first split)
  Duration _turnDuration = const Duration(seconds: 20);
  // The duration after which a word is checked whether it is right or wrong (fired after every completion)
  final Duration _validateDuration = const Duration(milliseconds: 650);
  // The duration after which a word is reset when it is wrong (fired after every completion)
  final Duration _resetWordDuration = const Duration(milliseconds: 2000);
  
  // Duration of the split animation
  final Duration _splitDuration = const Duration(milliseconds: 300);
  
  // The player's score
  int _score = 0;
  // The current word that was split
  String _currentWord = "";
  // The new word part that the player wrote
  String _newWordPart = "";
  // The vissible part of the current word after being cut
  String visiblePart = "";
  
  // The index where the current word was split
  int _currentSplitIndex = 0;
  // The number of found words
  int _foundWords = 0;
  // Boolean about whether the app is loading or not
  bool _isLoading = true;
  
  // Boolean indicating which side of the word is hidden
  bool _leftSideHidden = false;
  // The index of the starting color
  int _backgroundColorIndex = 0;
  // The index of the split color
  int _splitColorIndex = 0;

  // List with all the possible starter words (easier and with more following word options)
  List<String> _allStarterWords = []; // Loaded from starter_answers.txt
  // List with all possible valid words
  List<String> _allValidWords = [];  // Loaded from english_cleaned.txt
  // List with all the tiles for writing a new word
  List<String> _availableTiles = [];

  // A List of the previous words a player has found
  final List<String> _previousWords = [];

  // Animation controllers
  late final AnimationController _controller;
  late final Animation<double> opacity;
  late final AnimationController _highlightController;
  late final Animation<double> highlightPosition;

  GamePhase _phase = GamePhase.starting;
  GamePhase _prevPhase = GamePhase.starting;

  // Timer used for the validation process
  Timer? _validationTimer;
  // Timer used for the word reset process
  Timer? _resetWordTimer;
  // Timer for the turn countdown
  Timer? _turnTimer;
  // Remaining time in the current turn
  Duration _remainingTime = const Duration(seconds: 0);

  @override
  void initState() {
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 1300),
      vsync: this,
    );

    highlightPosition = Tween<double>(begin: 0.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _highlightController,
        curve: Curves.easeInOut,
      ),
    );

    final random = Random();
    _backgroundColorIndex = random.nextInt(Colors.primaries.length);
    _splitColorIndex = (_backgroundColorIndex+2)%Colors.primaries.length;

    _initializeGame();
    super.initState();
  }

  Future<void> _loadStarterWords() async {
    final content = await rootBundle.loadString('assets/word_lists/starter_answers.txt');
    _allStarterWords = content.split('\n').map((e) => e.toLowerCase().trim()).where((w) => w.length > 2).toList();
  }

  Future<void> _loadValidWords() async {
    final content = await rootBundle.loadString('assets/word_lists/english_cleaned.txt');
    _allValidWords = content.split('\n').map((e) => e.toLowerCase().trim()).where((w) => w.length > 2).toList();
  }

  Future<void> _initializeGame() async {
    setState(() {
      _isLoading = true;
    });
    await _loadStarterWords();

    await _loadValidWords();

    final random = Random();
    _currentWord = _allStarterWords[random.nextInt(_allStarterWords.length)];

    _previousWords.clear();
    _previousWords.add(_currentWord);
    
    _score = 0;
    _foundWords = 0;
    _turnDuration = const Duration(seconds: 20);

    _controller.forward(from: 0.0);
    setState(() {
      _isLoading = false;
      _phase = GamePhase.starting;
    });

    _nextTurn(_currentWord);
  }

  void _startTurnTimer({bool resumed = false}) {
    _turnTimer?.cancel();
    if (!resumed) {
      _remainingTime = _turnDuration;
    }
    _turnTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_remainingTime.inMilliseconds > 0) {
        setState(() {
          _remainingTime = _remainingTime - const Duration(milliseconds: 50);
        });
      } else {
        _gameOver();
      }
    });
  }

  void _gameOver() {
    _validationTimer?.cancel();
    _resetWordTimer?.cancel();
    _turnTimer?.cancel();
    setState(() {
      _phase = GamePhase.gameOver;
    });
  }

  Future<void> _nextTurn(foundWord) async {
    _currentWord = foundWord;
    // Decrease turn duration, with a minimum of 5 seconds
    if (_turnDuration.inSeconds > 5) {
      _turnDuration -= const Duration(seconds: 1);
    }

    _startTurnTimer();

    final random = Random();
    int simpleRand = random.nextInt(2);
    _newWordPart = "";
    setState(() {
      _leftSideHidden = !_leftSideHidden;
      if (_currentWord.length == 3) {
        _currentSplitIndex = 1 + simpleRand;
      } else
      if (_currentWord.length >= 6) {
        if (!_leftSideHidden) {
            _currentSplitIndex = 2+simpleRand;
          } else {
            _currentSplitIndex =_currentWord.length - 2-simpleRand;
          }
      } else {
        _currentSplitIndex = 2 + random.nextInt(_currentWord.length - 3);
      }

      visiblePart = _leftSideHidden ? _currentWord.substring(_currentSplitIndex) : _currentWord.substring(0, _currentSplitIndex);

      _phase = GamePhase.startSplit;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _phase = GamePhase.splitting;
        _generateTiles();
      });
    });
    Future.delayed(_splitDuration, () {
      setState(() {
        _phase = GamePhase.splitWord;
      });
    });
  }
  
  void _generateTiles() async {
    final starterCandidates = _allStarterWords.where((word) {
      if (_previousWords.contains(word)) return false;
      return _leftSideHidden ? word.endsWith(visiblePart) : word.startsWith(visiblePart);
    }).toList();

    final candidates = _allValidWords.where((word) {
      if (_previousWords.contains(word)) return false;
      return _leftSideHidden ? word.endsWith(visiblePart) : word.startsWith(visiblePart);
    }).toList();

    final starterMissingParts = starterCandidates
        .map((w) => _leftSideHidden
            ? w.substring(0, w.length - visiblePart.length)
            : w.substring(visiblePart.length))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    print("//////////// STARTER CANDIDATES");
    print(starterCandidates);
    print("//////////// CANDIDATES");
    print(candidates);

    final missingParts = candidates
        .map((w) => _leftSideHidden
            ? w.substring(0, w.length - visiblePart.length)
            : w.substring(visiblePart.length))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    starterMissingParts.shuffle();
    missingParts.shuffle();

    const maxTiles = 10;

    // ⛑ fallback letters if everything else fails
    List<String> fallbackLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

    final starterPickedParts = starterMissingParts.take(1).toList();
    final starterGuaranteedLetters = starterPickedParts.expand((s) => s.split('')).toSet().toList();
    List<String> keptGuaranteed = starterGuaranteedLetters.take(maxTiles).toList();

    final pickedParts = missingParts.take(3).toList();
    final guaranteedLetters = pickedParts.expand((s) => s.split('')).toSet().toList();
    keptGuaranteed.addAll(
        guaranteedLetters.take(maxTiles - keptGuaranteed.length).toList());

    keptGuaranteed = keptGuaranteed.take(maxTiles).toList();

    List<String> totalTiles = List.empty(growable: true);

    if (keptGuaranteed.isEmpty) {
      // ❗ Fallback if no candidates matched
      totalTiles = fallbackLetters.take(maxTiles).toList();
    } else if (keptGuaranteed.length < maxTiles) {
      final fillerLetters = missingParts
          .skip(pickedParts.length)
          .expand((s) => s.split(''))
          .where((ch) => !keptGuaranteed.contains(ch))
          .toSet()
          .toList();

      fillerLetters.shuffle();

      final remainingSlots = maxTiles - keptGuaranteed.length;
      totalTiles = [
        ...keptGuaranteed,
        ...fillerLetters.take(remainingSlots),
      ];
    } else {
      totalTiles = keptGuaranteed;
    }

    // Remove duplicates
    totalTiles = totalTiles.toSet().toList();

    // If fewer than 10 left, add random filler letters until we reach maxTiles
    while (totalTiles.length < maxTiles) {
      final randomLetter = (fallbackLetters..shuffle()).first;
      if (!totalTiles.contains(randomLetter)) {
        totalTiles.add(randomLetter);
      }
    }

    totalTiles.shuffle();

    setState(() {
      _availableTiles = totalTiles.take(maxTiles).toList();
    });

  }

  void _resumeGame() {
    _startTurnTimer(resumed: true);
    setState(() {
      _phase = _prevPhase;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _highlightController.dispose();
    _validationTimer?.cancel();
    _resetWordTimer?.cancel();
    _turnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SizedBox.expand( // ✅ Ensures Stack has bounded constraints
        child:Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(seconds: 1),
            width:totalWidth,
            height: height,
            color: Colors.primaries[_backgroundColorIndex].shade300,
          ),
          // The word before it is split and after it is split (the famous previous-found or starting word)
          if ((_phase == GamePhase.starting || _phase == GamePhase.startSplit || _phase == GamePhase.splitting || _phase == GamePhase.splitWord) && !_isLoading)
          Positioned(
            left: 20,
            top: 0,
            child: FadeTransition(
              opacity: opacity,
              child: SizedBox(
                width: totalWidth-40,
                height: height * 0.66,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    _currentWord,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The current word part needed for merging
          if ((_phase == GamePhase.startMerging || _phase == GamePhase.merging) && !_isLoading)
          _leftSideHidden == false?
          Positioned(
            left: -22,
            top: 0,
            child: AnimatedContainer(
              alignment: Alignment.topRight,
              duration: _splitDuration,
              width: 42+(totalWidth-40)*_currentSplitIndex/(_currentWord.length),
              height: height,
              color: Colors.primaries[_backgroundColorIndex].shade300,
              child: Container(
                margin: const EdgeInsets.only(left: 40),
                width: 22+(totalWidth-40)*_currentSplitIndex/(_currentWord.length),
                height: height*0.66,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    visiblePart,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                )
              )
            ),
          ):
          Positioned(
            right: -22,
            top: 0,
            child: AnimatedContainer(
              alignment: Alignment.topLeft,
              duration: _splitDuration,
              width: 42+(totalWidth-40)*((_currentWord.length) - _currentSplitIndex)/(_currentWord.length),
              height: height,
              color: Colors.primaries[_backgroundColorIndex].shade300,
              child: Container(
                margin: const EdgeInsets.only(right: 40),
                width: 22+(totalWidth-40)*((_currentWord.length) - _currentSplitIndex)/(_currentWord.length),
                height: height*0.66,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    visiblePart,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                )
              )
            ),
          ),
          // Split Color
          if ((_phase == GamePhase.splitting || _phase == GamePhase.splitWord || _phase == GamePhase.startMerging || _phase == GamePhase.merging || _phase == GamePhase.startSplit) && !_isLoading)
          _leftSideHidden?
          Positioned(
            left: -22,
            top: 0,
            child: AnimatedContainer(
              alignment: Alignment.topRight,
              duration: _splitDuration,
              width: _phase == GamePhase.startSplit? 21 : 42+(totalWidth-40)*_currentSplitIndex/(_currentWord.length),
              height: height,
              color: Colors.primaries[_splitColorIndex].shade300,
              child: Container(
                margin: EdgeInsets.only(left: _phase == GamePhase.startSplit? 0: 40),
                width: _phase == GamePhase.startSplit? 1 : 22+(totalWidth-40)*_currentSplitIndex/(_currentWord.length),
                height: height*0.66,
                child: _phase == GamePhase.startSplit?
                const SizedBox.expand() : FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    _newWordPart,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                )
              )
            ),
          ):
          Positioned(
            right: -22,
            top: 0,
            child: AnimatedContainer(
              alignment: Alignment.topLeft,
              duration: _splitDuration,
              width: _phase == GamePhase.startSplit? 21 : 42+(totalWidth-40)*((_currentWord.length) - _currentSplitIndex)/(_currentWord.length),
              height: height,
              color: Colors.primaries[_splitColorIndex].shade300,
              child: Container(
                margin: EdgeInsets.only(right: _phase == GamePhase.startSplit? 0: 40),
                width: _phase == GamePhase.startSplit? 1 : 22+(totalWidth-40)*((_currentWord.length) - _currentSplitIndex)/(_currentWord.length),
                height: height*0.66,
                child: _phase == GamePhase.startSplit?
                const SizedBox.expand() : FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    _newWordPart,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                )
              )
            ),
          ),
          // When word is formed, show as one complete text with highlight
          if (_phase == GamePhase.formedWord && !_isLoading)
          Positioned(
            left: 20,
            top: 0,
            child: FadeTransition(
              opacity: opacity,
              child: SizedBox(
                width: totalWidth-40,
                height: height * 0.66,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: AnimatedBuilder(
                    animation: highlightPosition,
                    builder: (context, child) {
                      final sweepX = highlightPosition.value;
                      const highlightWidth = 0.25; // Width of highlight beam (25% of screen)
                      
                      return ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              // Main sweep highlight
                              sweepX<1.2 || sweepX%0.4>0.2?
                              Colors.black:
                              Colors.white,
                              (sweepX>0.99 && sweepX<1.2) || (sweepX%0.4>0.2)?
                              Colors.black:
                              Colors.white,
                              sweepX<1.2 || sweepX%0.4>0.2?
                              Colors.black:
                              Colors.white,
                            ],
                            stops: [
                              (sweepX - highlightWidth / 2).clamp(0.0, 0.99),
                              sweepX.clamp(0.01, 1.0),
                              (sweepX + highlightWidth / 2).clamp(0.01, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          _newWordPart,
                          style: const TextStyle(
                            fontFamily: "SpaceMono",
                            fontSize: 100,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_phase == GamePhase.gameOver)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Game Over',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 118, 15, 15),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Final Score: $_score',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Found Words: $_foundWords',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  MaterialButton(
                    onPressed: _initializeGame,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DB6AC),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: Colors.black,
                          width: 4,
                        ),
                      ),
                      child: const Text(
                        'Restart',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    )
                  )
                ],
              ),
            ),
          ),
          if (_phase == GamePhase.pauseGame)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Paused',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Score: $_score',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Found Words: $_foundWords',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  MaterialButton(
                    onPressed: _resumeGame,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DB6AC),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: Colors.black,
                          width: 4,
                        ),
                      ),
                      child: const Text(
                        'Resume',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    )
                  )
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 6, 4),
                    child: Text(
                      'Score: $_score',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (_phase == GamePhase.startSplit && _phase == GamePhase.splitting && _phase == GamePhase.splitWord)
                      IconButton(
                        icon: const Icon(Icons.pause),
                        iconSize: 32,
                        color: Colors.black,
                        onPressed: () {
                          setState(() {
                            _prevPhase = _phase;
                            _phase = GamePhase.pauseGame;
                          });
                          if (_turnTimer != null && _turnTimer!.isActive) {
                            _turnTimer!.cancel();
                          } else {
                            _startTurnTimer();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 32,
                        color: Colors.black,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _prevPhase = _phase;
                            _phase = GamePhase.pauseGame;
                          });
                          if (_turnTimer != null && _turnTimer!.isActive) {
                            _turnTimer!.cancel();
                          } else {
                            _startTurnTimer();
                          }
                        },
                      ),
                    ],
                  )
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Container(
                  alignment: Alignment.centerLeft,
                  width: totalWidth-40,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.black, width: 4),
                  ),
                  child: ClipRRect(
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 50),
                      width: (totalWidth-40)*(_remainingTime.inMilliseconds / _turnDuration.inMilliseconds),
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DB6AC),
                        borderRadius: BorderRadius.circular(4.0)
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          if (_phase == GamePhase.splitWord && _availableTiles.isNotEmpty)
            SizedBox(
              width: totalWidth,
              height: height,
            child: SwipePathTyper(
              tiles: _availableTiles,
              columnCount: 5,
              simpleTapMode: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              horizontalTileSpacing: 12,
              verticalTileSpacing: 12,
              tileBuilder: (context, letter, isSelected) => TileButton(
                letter: letter,
                isSelected: isSelected,
              ),
              swipeTrailColor: Colors.black87,
              swipeTrailStrokeWidth: 8.0,
              onLetterSelected: (letter) {
                setState(() {
                  _newWordPart +=letter;
                  _newWordPart = _newWordPart.toLowerCase().trim();
                });
              },
              onSwipeCompleted: (word) {
                visiblePart = _leftSideHidden ? _currentWord.substring(_currentSplitIndex) : _currentWord.substring(0, _currentSplitIndex);
                
                if (_validationTimer != null && _validationTimer!.isActive) {
                  _validationTimer!.cancel();
                }
                _validationTimer = Timer(_validateDuration, () {
                  if (_currentWord.isNotEmpty && _newWordPart.isNotEmpty) {
                    String formedWord = _leftSideHidden ? _newWordPart + visiblePart : visiblePart + _newWordPart;
                    if(formedWord.length < 3){
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('The word must be at least three-char long'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                    else
                    if (_allValidWords.contains(formedWord) && !_previousWords.contains(formedWord)) {
                       // Scoring: length of new part * remaining time
                      setState(() {
                        _foundWords++;
                        _score += ((_newWordPart.length+formedWord.length * (_remainingTime.inSeconds/_turnDuration.inSeconds))*10).floor();
                      });

                      _turnTimer?.cancel();
                      if (_resetWordTimer != null && _resetWordTimer!.isActive) {
                        _resetWordTimer!.cancel();
                      }
                      bool mergeNeeded = true;

                      if (formedWord.length == _currentWord.length){
                        mergeNeeded = false;
                      }

                      if (mergeNeeded) {
                        setState(() {
                          _phase = GamePhase.startMerging;
                        });
                        Future.delayed(const Duration(milliseconds: 100), () {
                          setState(() {
                            _currentWord = formedWord;
                            _currentSplitIndex = _leftSideHidden ? _newWordPart.length : visiblePart.length;
                            _phase = GamePhase.merging;
                          });
                        });
                      }
                      Future.delayed(const Duration(milliseconds: 350), () {
                        setState(() {
                          _previousWords.add(formedWord);
                          if (_previousWords.length > 20) {
                            _previousWords.removeAt(0);
                          }
                          _newWordPart = formedWord;
                          _backgroundColorIndex = _splitColorIndex;
                          _splitColorIndex = (_backgroundColorIndex+2)%Colors.primaries.length;
                          _phase = GamePhase.formedWord;
                        });
                        _highlightController.forward(from: 0.0);
                      });
                      Future.delayed(const Duration(milliseconds: 1600), () {
                        _nextTurn(formedWord);
                      });
                    }
                    else if (_previousWords.contains(formedWord)) {
                      // Already used word feedback
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Word was used recently'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  }
                });

                if (_resetWordTimer != null && _resetWordTimer!.isActive) {
                  _resetWordTimer!.cancel();
                }
                _resetWordTimer = Timer(_resetWordDuration, () {
                  setState(() {
                    _newWordPart = "";
                    _currentWord = _previousWords.isNotEmpty ? _previousWords.last : _currentWord;
                    _phase = GamePhase.splitWord;
                  });
                });
              },
            ),
          )
        ],
      )),
    );
  }
}


class TileButton extends StatelessWidget {
  final String letter;
  final bool isSelected;

  const TileButton({
    super.key,
    required this.letter,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Colors.black;

    return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? const Color.fromARGB(255, 54, 129, 121) : const Color(0xFF4DB6AC),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: themeColor,
            width: 4,
          ),
        ),
        child: Text(
          letter.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: "SpaceMono",
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
    );
  }
}