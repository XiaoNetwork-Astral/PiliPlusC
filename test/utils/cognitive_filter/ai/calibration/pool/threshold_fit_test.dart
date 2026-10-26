import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/threshold_fit.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Answered = ({CalibrationAnswer answer, List<double> scores});

_Answered _answer(CalibrationAnswer answer, List<double> scores) {
  return (answer: answer, scores: scores);
}

List<_Answered> _repeat(
  CalibrationAnswer answer,
  List<double> scores,
  int count,
) {
  return <_Answered>[
    for (var i = 0; i < count; i++) _answer(answer, List<double>.of(scores)),
  ];
}

void main() {
  test('全是不该拦的高分成员时门槛上移', () {
    final answers = _repeat(CalibrationAnswer.keep, <double>[0.9], 8);
    final fitted = fitThreshold(current: 0.7, answers: answers);

    expect(fitted, isNotNull);
    expect(fitted!, greaterThan(0.7));
    expect(fitted, lessThanOrEqualTo(0.97));
    expect(fitted, closeTo(0.835, 1e-9));
  });

  test('全是该拦的低分成员时门槛下移', () {
    final answers = <_Answered>[
      for (var i = 0; i < 8; i++)
        _answer(CalibrationAnswer.block, <double>[i.isEven ? 0.65 : 0.70]),
    ];
    final fitted = fitThreshold(current: 0.8, answers: answers);

    expect(fitted, isNotNull);
    expect(fitted!, lessThan(0.8));
    expect(fitted, closeTo(0.7, 1e-9));
  });

  test('误拦代价是漏拦的 2 倍时门槛停在高位', () {
    final answers = <_Answered>[
      ..._repeat(CalibrationAnswer.keep, <double>[0.8], 4),
      ..._repeat(CalibrationAnswer.block, <double>[0.7], 5),
    ];

    final costly = fitThreshold(
      current: 0.75,
      answers: answers,
      falseBlockCost: 2,
    );
    final cheap = fitThreshold(
      current: 0.75,
      answers: answers,
      falseBlockCost: 1,
    );

    expect(costly, closeTo(0.86, 1e-9));
    expect(cheap, closeTo(0.675, 1e-9));
  });

  test('参与题数少于 minAnswers 时不调整', () {
    final seven = _repeat(CalibrationAnswer.keep, <double>[0.9], 7);
    expect(fitThreshold(current: 0.7, answers: seven), isNull);
    expect(fitThreshold(current: 0.7, answers: <_Answered>[]), isNull);

    final enough = _repeat(CalibrationAnswer.keep, <double>[0.9], 8);
    expect(fitThreshold(current: 0.7, answers: enough), isNotNull);
  });

  test('skip 不参与计数与代价', () {
    final answers = <_Answered>[
      ..._repeat(CalibrationAnswer.skip, <double>[0.99], 8),
      _answer(CalibrationAnswer.keep, <double>[0.9]),
    ];
    expect(fitThreshold(current: 0.7, answers: answers), isNull);
  });

  test('代价并列时取离 current 最近的，仍并列取较大者', () {
    final answers = _repeat(CalibrationAnswer.block, <double>[0.1], 8);
    // 所有候选代价相同；0.5 与 1.0 离 0.75 等距，应取 1.0
    final fitted = fitThreshold(
      current: 0.75,
      answers: answers,
      lower: 0.5,
      upper: 1.0,
    );

    expect(fitted, closeTo(0.875, 1e-9));
  });

  test('current 在区间外时结果仍会钳位', () {
    final keepHigh = _repeat(CalibrationAnswer.keep, <double>[0.9], 8);

    expect(fitThreshold(current: 0.2, answers: keepHigh), closeTo(0.6, 1e-9));
    expect(
      fitThreshold(current: 1.2, answers: keepHigh),
      closeTo(0.97, 1e-9),
    );
  });

  test('候选门槛来自相邻得分中点并限制在区间内', () {
    final answers = <_Answered>[
      ..._repeat(CalibrationAnswer.keep, <double>[0.8], 4),
      ..._repeat(CalibrationAnswer.block, <double>[0.7], 4),
    ];
    // 候选为 0.6、0.75、0.97；0.75 的代价为 8 + 4 = 12，
    // 0.6 的代价为 8，0.97 的代价为 4，取 0.97
    final fitted = fitThreshold(current: 0.7, answers: answers);
    expect(fitted, closeTo(0.835, 1e-9));
  });
}
