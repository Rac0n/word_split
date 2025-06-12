import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const MyApp());
}

enum GamePhase {
  starting,     // Phase 1: full word, full canvas
  splitWord,    // Phase 2: split view, one side hidden
  formedWord,   // Phase 3: new word formed
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
  Duration _turnDuration = const Duration(seconds: 60);
  int _score = 0;
  String _currentWord = "";
  final List<int> _currentSplitIndexes = [0];
  int _currentTurn = 0;
  bool _isLoading = true;
  final List<int> _currentColorsIndexes = [0];
  bool _leftSideHidden = false;
  int _startColorIndex = 0;

  late final AnimationController _controller;
  late final Animation<double> opacity;

  GamePhase _phase = GamePhase.starting;


  @override
  void initState() {
    super.initState();

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

    _initializeGame();
  }

  Future<void> _initializeGame() async {
    final starterContent = await rootBundle.loadString('assets/word_lists/starter_answers.txt');
    final List<String> starterWords = starterContent.split('\n').map((e) => e.trim()).toList();

    final random = Random();
    _currentWord = starterWords[random.nextInt(starterWords.length)];

    _controller.forward(from: 0.0);
    setState(() {
      _isLoading = false;
    });

    await Future.delayed(const Duration(seconds: 2));

    _currentSplitIndexes.clear();
  
    setState((){
      if (_currentWord.length == 3) {
        _currentSplitIndexes.add(1 + random.nextInt(2));
      } else {
        _currentSplitIndexes.add(2 + random.nextInt(_currentWord.length - 3));
      }

      _leftSideHidden = random.nextBool();

      _phase = GamePhase.splitWord;
    });
  }

  Widget buildSplitText(String word, List<int> splitIndexes) {
    final splitPoints = [0, ...splitIndexes, word.length];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(splitPoints.length - 1, (i) {
        final segment = word.substring(splitPoints[i], splitPoints[i + 1]);

        return Expanded(
          flex: segment.length, // proportional space
          child: Container(
            color: Colors.primaries[(i + _startColorIndex) % Colors.primaries.length].shade300,
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
    print("Width of the screen: ${MediaQuery.of(context).size.width}");
    print("Height of the screen: ${MediaQuery.of(context).size.height}");

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _isLoading?
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.primaries[_currentColorsIndexes[0]].shade300,
          ):
          FadeTransition(
            opacity: opacity,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child:CustomPaint(
                size: Size.infinite,
                foregroundPainter: WordPainter(
                  word: _currentWord,
                  splitIndexes: _currentSplitIndexes,
                  colorIndexes: _currentColorsIndexes,
                ),
              )
            )
          ),
          if (!_isLoading)
          FadeTransition(
            opacity: opacity,
            child: Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              height: double.infinity,
              child: buildSplitText(_currentWord, _currentSplitIndexes),
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
              // Future tiles or input UI goes here
            ],
          ),
        ],
      ),
    );
  }
}

class WordPainter extends CustomPainter {
  final String? word;
  final List<int> splitIndexes;
  final List<int> colorIndexes;
  final Paint _paint = Paint();

  WordPainter({
    required this.word,
    required this.splitIndexes,
    required this.colorIndexes,
  });

  bool listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(covariant WordPainter oldDelegate) {
    return !listEquals(splitIndexes, oldDelegate.splitIndexes);
  }


  @override
  void paint(Canvas canvas, Size size) {
    final totalWidth = size.width-0.1;
    final height = size.height-0.1;

    if (word == null || word!.isEmpty) return; // No word to draw

    print("Size width: ${size.width}, Size height: ${size.height}, Word: $word, SplitIndexes: $splitIndexes, ColorIndexes: $colorIndexes");

    final splitPoints = [0, ...splitIndexes, word!.length];
    final totalLetters = word!.length;

    double currentX = 0;

    final List<double> charWidths = [];
    for (int i = 0; i < splitPoints.length - 1; i++) {
      final segmentLength = splitPoints[i + 1] - splitPoints[i];
      if (segmentLength <= 0) return; // Invalid segment
      final width = totalWidth * (segmentLength / totalLetters);
      charWidths.add(width);
    }

    for (int i = 0; i < charWidths.length; i++) {
      _paint.color = colorIndexes.isEmpty? Colors.primaries[0]: Colors.primaries[(i>= colorIndexes.length?colorIndexes[colorIndexes.length-1]:colorIndexes[i]) % Colors.primaries.length].shade300;

      double realCurrentX = currentX-1<=0? 0: currentX-1;


      canvas.drawRect(Rect.fromLTWH(realCurrentX, 0, realCurrentX+ charWidths[i]+2>=totalWidth? totalWidth-realCurrentX: charWidths[i]+2, height), _paint);
      currentX += charWidths[i];
    }
  }

}
