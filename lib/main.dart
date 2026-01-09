import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:swipe_path_typer/swipe_path_typer.dart';

void main() {
  runApp(const MyApp());
}

enum GamePhase {
  starting,     // Phase 1: full word, full canvas
  startSplit,    // Phase 2: start of the split process
  splitting,    // Phase 3: split process and animation
  splitWord,    // Phase 4: split view, one side hidden
  merging,      // Phase 5: Merge the two parts of the new word
  formedWord,   // Phase 6: new word formed
  gameOver,     // Final Game Phase: game over
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
  final Duration _turnDuration = const Duration(seconds: 60);
  // The duration after which a word is checked whether it is right or wrong (fired after every completion)
  final Duration _validateDuration = const Duration(milliseconds: 800);
  // The duration after which a word is reset when it is wrong (fired after every completion)
  final Duration _resetWordDuration = const Duration(milliseconds: 3000);
  // The player's score
  final int _score = 0;
  // The current word that was split
  String _currentWord = "";
  // The new word formed by the split word's part and what the player wrote
  String _newWord = "";
  // The two different word parts
  final List<String> _wordParts = [""];
  // The index where the current word was split
  final int _currentSplitIndex = 0;
  // The current turn number
  int _currentTurn = 0;
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

  // Whether the first letter was selected or not
  bool _firstLetterSelected = false;

  // A List of the previous words a player has found
  final List<String> _previousWords = [];

  // Animation controllers
  late final AnimationController _controller;
  late final Animation<double> opacity;
  late final AnimationController _highlightController;
  late final Animation<double> highlightPosition;

  GamePhase _phase = GamePhase.starting;

  // Timer used for the validation process
  Timer? _validationTimer;
  // Timer used for the word reset process
  Timer? _resetWordTimer;

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
      duration: const Duration(milliseconds: 1600),
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
    _splitColorIndex = (_backgroundColorIndex+1)%Colors.primaries.length;

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
    await _loadStarterWords();

    await _loadValidWords();

    final random = Random();
    _currentWord = _allStarterWords[random.nextInt(_allStarterWords.length)];

    _previousWords.add(_currentWord);

    _controller.forward(from: 0.0);
    setState(() {
      _isLoading = false;
    });

    await Future.delayed(const Duration(seconds: 2));
    _currentTurn += 1;
  
    setState((){
      if (_currentWord.length == 3) {
        _currentSplitIndex = 1 + random.nextInt(2);
      } else {
        _currentSplitIndex = 2 + random.nextInt(_currentWord.length - 3);
      }

      _leftSideHidden = random.nextBool();

      _phase = GamePhase.startSplit;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _phase = GamePhase.splitting;
        _generateTiles();
      });
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _phase = GamePhase.splitWord;
      });
    });
  }
  
  void _generateTiles() async {
    final visiblePart = _leftSideHidden
        ? _currentWord.substring(_currentSplitIndex)
        : _currentWord.substring(0, _currentSplitIndex);

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

  @override
  void dispose() {
    _controller.dispose();
    _highlightController.dispose();
    _validationTimer?.cancel();
    _resetWordTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    final totalLetters = _currentWord.length;

    _wordParts.clear();

    final List<double> charWidths = [];
    _wordParts.add(_currentWord.substring(0, _currentSplitIndex));
    _wordParts.add(_currentWord.substring(_currentSplitIndex));

    return Scaffold(
      body: SizedBox.expand( // ✅ Ensures Stack has bounded constraints
        child:Stack(
        children: [
          Container(
            width:totalWidth,
            height: height,
            color: Colors.primaries[_backgroundColorIndex].shade300,
          ),
          // Split Color
          if ((_phase == GamePhase.splitting || _phase == GamePhase.splitWord || _phase == GamePhase.merging) && !_isLoading)
          _leftSideHidden?
          Positioned(
            left: 0,
            top: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 20+(totalWidth-40)*_currentSplitIndex/totalLetters,
              height: height,
              color: Colors.primaries[_splitColorIndex].shade300,
            ),
          ):
          Positioned(
            left: 20+(totalWidth-40)*_currentSplitIndex/totalLetters,
            top: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 20+(totalWidth-40)*(totalLetters - _currentSplitIndex)/totalLetters,
              height: height,
              color: Colors.primaries[_splitColorIndex].shade300,
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
                          _newWord,
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
          // Split text parts only shown in other phases
          if (_phase != GamePhase.formedWord)
          for (int i = 0; i < charWidths.length; i++)
          if (!_isLoading && (_phase != GamePhase.splitWord || (_phase == GamePhase.splitWord && (_leftSideHidden?(i!=0):(i!=charWidths.length-1)))))
          Positioned(
            left: currentXs[i]-1 <0? 0: currentXs[i]-1,
            top: 0,
            child: FadeTransition(
              opacity: opacity,
              child: SizedBox(
                width: currentXs[i] + charWidths[i] + 2>totalWidth? totalWidth - currentXs[i] + 1: charWidths[i] + 2,
                height: height*0.66,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    _currentWord.substring(splitPoints[i], splitPoints[i + 1]),
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              )
            )
          ),
          if((_phase == GamePhase.startSplit || _phase==GamePhase.splitting || _phase==GamePhase.splitWord) && !_isLoading)
          (_leftSideHidden?
          Positioned(
            left: 0,
            top: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 222),
              width: _phase==GamePhase.startSplit?0:charWidths[0]+2,
              height: height,
              color: Colors.primaries[_currentColorsIndexes[0]%Colors.primaries.length].shade300,
            ),
          ):
          AnimatedPositioned(
            duration: const Duration(milliseconds: 222),
            right: _phase==GamePhase.startSplit?-charWidths.last-1:0,
            top: 0,
            child: Container(
              width: charWidths.last+2,
              height: height,
              color: Colors.primaries[_currentColorsIndexes.last%Colors.primaries.length].shade300,
            ),
          )),
          for (int i = 0; i < charWidths.length; i++)
          if (!_isLoading && _phase == GamePhase.splitWord && (_leftSideHidden?(i==0):(i==charWidths.length-1)))
          Positioned(
            left: currentXs[i]-1 <0? 0: currentXs[i]-1,
            top: 0,
            child: FadeTransition(
              opacity: opacity,
              child: SizedBox(
                width: currentXs[i] + charWidths[i] + 2>totalWidth? totalWidth - currentXs[i] + 1: charWidths[i] + 2,
                height: height*0.66,
                child: FittedBox(
                  alignment: _leftSideHidden ? Alignment.centerRight : Alignment.centerLeft,
                  fit: BoxFit.contain,
                  child: Text(
                    _newWord,
                    style: const TextStyle(
                      fontFamily: "SpaceMono",
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              )
            )
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
                      IconButton(
                        icon: const Icon(Icons.pause),
                        iconSize: 28,
                        color: Colors.black,
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 28,
                        color: Colors.black,
                        icon: const Icon(Icons.menu),
                        onPressed: () {},
                      ),
                    ],
                  )
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 4),
                  ),
                  child: ClipRRect(
                    clipBehavior: Clip.antiAlias,
                    child: LinearProgressIndicator(
                      value: _turnDuration.inSeconds / 60,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
                      minHeight: 12,
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
                  if(!_firstLetterSelected){
                    _firstLetterSelected = true;
                    _newWord +=letter;
                  }
                  else {
                    _newWord +=letter;
                  }
                  _newWord = _newWord.toLowerCase().trim();
                });
                // Optional: handle letter selection (e.g., update UI)
                print("Letter selected: $letter");
              },
              onSwipeCompleted: (word) {
                // Optional: handle the completed word (score, validation, etc)
                print("User swiped/tapped: $word");
                String visiblePart = _leftSideHidden ? _currentWord.substring(_currentSplitIndexes[0]) : _currentWord.substring(0, _currentSplitIndexes[0]);
                print("Current visible part: $visiblePart");
                print(_currentColorsIndexes.toString());
                print("Current split indexes: $_currentSplitIndexes");

                if (_validationTimer != null && _validationTimer!.isActive) {
                  _validationTimer!.cancel();
                }
                _validationTimer = Timer(_validateDuration, () {
                  if (_currentWord.isNotEmpty && _newWord.isNotEmpty) {
                    String formedWord = _leftSideHidden ? _newWord + visiblePart : visiblePart + _newWord;
                    _firstLetterSelected = false;
                    if (_allValidWords.contains(formedWord) && !_previousWords.contains(formedWord)) {
                      setState(() {
                        _previousWords.add(formedWord);
                        if (_previousWords.length > 10) {
                          _previousWords.removeAt(0);
                        }
                        _phase = GamePhase.formedWord;
                      });
                      _highlightController.forward(from: 0.0);
                      Future.delayed(const Duration(milliseconds: 800), () {
                        // _initializeGame();
                      });
                    }
                    else if (_previousWords.contains(formedWord)) {
                      // Already used word feedback
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Word was already used recently: $formedWord'),
                          duration: const Duration(seconds: 1),
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
                    _newWord = "";
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
          borderRadius: BorderRadius.circular(12),
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
