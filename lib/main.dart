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
  final int _score = 0;
  String _currentWord = "";
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

  final List<String> _previousWords = [];

  late final AnimationController _controller;
  late final Animation<double> opacity;

  GamePhase _phase = GamePhase.starting;


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
    _allStarterWords = content.split('\n').map((e) => e.trim()).where((w) => w.length > 2).toList();
  }

  Future<void> _loadValidWords() async {
    final content = await rootBundle.loadString('assets/word_lists/english_cleaned.txt');
    _allValidWords = content.split('\n').map((e) => e.trim()).where((w) => w.length > 2).toList();
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
  const fallbackLetters = ['A', 'E', 'I', 'O', 'U', 'S', 'T', 'R', 'L', 'N'];

  final starterPickedParts = starterMissingParts.take(1).toList();
  final starterGuaranteedLetters = starterPickedParts.expand((s) => s.split('')).toSet().toList();
  List<String> keptGuaranteed = starterGuaranteedLetters.take(maxTiles).toList();

  final pickedParts = missingParts.take(3).toList();
  final guaranteedLetters = pickedParts.expand((s) => s.split('')).toSet().toList();
  keptGuaranteed.addAll(
      guaranteedLetters.take(maxTiles - keptGuaranteed.length).toList());

  keptGuaranteed = keptGuaranteed.take(maxTiles).toList();

  List<String> totalTiles;

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

  totalTiles.shuffle();

  setState(() {
    _availableTiles = totalTiles;
  });
}


  Widget buildSplitText(String word, List<int> splitPoints) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(splitPoints.length - 1, (i) {
        final segment = word.substring(splitPoints[i], splitPoints[i + 1]);

        return Expanded(
          flex: segment.length, // proportional space
          child: SizedBox(
            child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  segment,
                  style: const TextStyle(
                    fontFamily: "SpaceMono",
                    fontSize: 100,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
          ),
        );
      }),
    );
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
          if (!_isLoading)
            FadeTransition(
              opacity: opacity,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      width:totalWidth,
                      height: height,
                      child: buildSplitText(_currentWord, splitPoints),
                    )
                  ),SizedBox(height:180)
                ],
              )
            ),
          if((_phase == GamePhase.startSplit || _phase==GamePhase.splitting || _phase==GamePhase.splitWord) && !_isLoading)
          (_leftSideHidden?
          Positioned(
            left: 0,
            top: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 333),
              width: _phase==GamePhase.startSplit?0:charWidths[0]+2,
              height: height,
              color: Colors.primaries[_currentColorsIndexes[0]%Colors.primaries.length].shade300,
            ),
          ):
          AnimatedPositioned(
            duration: const Duration(milliseconds: 333),
            right: _phase==GamePhase.startSplit?-charWidths.last-1:0,
            top: 0,
            child: Container(
              width: charWidths.last+2,
              height: height,
              color: Colors.primaries[_currentColorsIndexes.last%Colors.primaries.length].shade300,
            ),
          )),
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
            SwipePathTyper(
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
              onWordCompleted: (word) {
                // Optional: handle the completed word (score, validation, etc)
                print("User swiped/tapped: $word");
              },
            ),
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
