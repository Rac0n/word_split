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
  startSplit,    // Phase 2: split process and animation
  splitting,    // Phase 2: split process and animation
  splitWord,    // Phase 3: split view, one side hidden
  formedWord,   // Phase 4: new word formed
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

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  final Duration _turnDuration = const Duration(seconds: 60);
  final Duration _validateDuration = const Duration(milliseconds: 800);
  final Duration _resetWordDuration = const Duration(milliseconds: 3333);
  final int _score = 0;
  String _currentWord = "";
  String _newWord = "";
  final List<String> _wordParts = [""];
  final List<int> _currentSplitIndexes = [0];
  int _currentTurn = 0;
  bool _isLoading = true;
  final List<int> _currentColorsIndexes = [0];
  final List<int> _prevColorsIndexes = [0];
  bool _leftSideHidden = false;
  int _startColorIndex = 0;
  List<String> _allStarterWords = []; // Loaded from starter_answers.txt
  List<String> _allValidWords = [];  // Loaded from english_cleaned.txt
  List<String> _availableTiles = [];

  bool _firstLetterSelected = false;

  final List<String> _previousWords = [];

  late final AnimationController _controller;
  late final Animation<double> opacity;

  GamePhase _phase = GamePhase.starting;

  Timer? _validationTimer;
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
    final random = Random();

    _currentColorsIndexes.clear();

    _startColorIndex = random.nextInt(Colors.primaries.length);
    _currentColorsIndexes.add(_startColorIndex);

    _prevColorsIndexes.clear();
    _prevColorsIndexes.add(_startColorIndex);

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
    if (_previousWords.length > 10) {
      _previousWords.removeAt(0);
    }

    _controller.forward(from: 0.0);
    setState(() {
      _isLoading = false;
    });

    await Future.delayed(const Duration(seconds: 2));
    _currentTurn += 1;

    _currentSplitIndexes.clear();
  
    setState((){
      if (_currentWord.length == 3) {
        _currentSplitIndexes.add(1 + random.nextInt(2));
      } else {
        _currentSplitIndexes.add(2 + random.nextInt(_currentWord.length - 3));
      }

      _leftSideHidden = random.nextBool();

      _prevColorsIndexes.clear();
      _prevColorsIndexes.addAll(_currentColorsIndexes);

      if (_leftSideHidden) {
        _currentColorsIndexes.insert(0, _startColorIndex+_currentTurn);
      } else {
        _currentColorsIndexes.add(_startColorIndex+_currentTurn);
      }

      _phase = GamePhase.startSplit;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _phase = GamePhase.splitting;
        _generateTiles();
      });
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _phase = GamePhase.splitWord;
      });
    });
  }
  
  void _generateTiles() async {
    final visiblePart = _leftSideHidden
        ? _currentWord.substring(_currentSplitIndexes[0])
        : _currentWord.substring(0, _currentSplitIndexes[0]);

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
  Widget build(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    final splitPoints = [0, ..._currentSplitIndexes, _currentWord.length];
    final totalLetters = _currentWord.length;

    double currentX = 0;

    List<double> currentXs = [];

    currentXs.add(0.0);

    _wordParts.clear();

    final List<double> charWidths = [];
    for (int i = 0; i < splitPoints.length - 1; i++) {
      _wordParts.add(_currentWord.substring(splitPoints[i], splitPoints[i + 1]));
      final segmentLength = splitPoints[i + 1] - splitPoints[i];
      final width = totalWidth * (segmentLength / totalLetters);
      charWidths.add(width);
      currentX += charWidths[i];
      currentXs.add(currentX);
    }

    return Scaffold(
      body: SizedBox.expand( // ✅ Ensures Stack has bounded constraints
        child:Stack(
        children: [
          if (_isLoading)
          Container(
            width:totalWidth,
            height: height,
            color: Colors.primaries[_startColorIndex%Colors.primaries.length].shade300,
          ),
          for (int i = 0; i < charWidths.length; i++)
          if (!_isLoading)
          Positioned(
            left: currentXs[i]-1 <0? 0: currentXs[i]-1,
            top: 0,
            child: FadeTransition(
              opacity: opacity,
              child: Container(
                width: currentXs[i] + charWidths[i] + 2>totalWidth? totalWidth - currentXs[i] + 1: charWidths[i] + 2,
                height: height,
                color: _phase == GamePhase.splitWord?
                (Colors.primaries[(i>= _currentColorsIndexes.length?_currentColorsIndexes[_currentColorsIndexes.length-1]:_currentColorsIndexes[i]) % Colors.primaries.length].shade300)
                :( Colors.primaries[(i>= _prevColorsIndexes.length?_prevColorsIndexes[_prevColorsIndexes.length-1]:_prevColorsIndexes[i]) % Colors.primaries.length].shade300)
              )
            )
          ),
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
                    padding: EdgeInsets.fromLTRB(20, 12, 6, 4),
                    child: Text(
                      'Score: $_score',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.pause),
                        iconSize: 28,
                        color: Colors.black,
                        onPressed: () {},
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        iconSize: 28,
                        color: Colors.black,
                        icon: Icon(Icons.menu),
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
              Expanded(child: SizedBox()),
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
                      Future.delayed(const Duration(milliseconds: 800), () {
                        // _initializeGame();
                      });
                    }
                    else if (_previousWords.contains(formedWord)) {
                      // Already used word feedback
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Word was already used recently: $formedWord'),
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
    final themeColor = Colors.black;

    return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Color.fromARGB(255, 54, 129, 121) : Color(0xFF4DB6AC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: themeColor,
            width: 4,
          ),
        ),
        child: Text(
          letter.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: "SpaceMono",
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
    );
  }
}
