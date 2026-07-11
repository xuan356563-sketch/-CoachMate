import '../models/meal_guide.dart';
import '../seed/seed_meal_guides.dart';

abstract class MealGuideRepository {
  List<MealGuide> listMealGuides();

  MealGuide findByScenario(MealScenario scenario);
}

class InMemoryMealGuideRepository implements MealGuideRepository {
  final List<MealGuide> _mealGuides;

  InMemoryMealGuideRepository({List<MealGuide>? initialMealGuides})
      : _mealGuides = List<MealGuide>.from(initialMealGuides ?? seedMealGuides);

  @override
  List<MealGuide> listMealGuides() {
    return List<MealGuide>.unmodifiable(_mealGuides);
  }

  @override
  MealGuide findByScenario(MealScenario scenario) {
    for (final MealGuide guide in _mealGuides) {
      if (guide.scenario == scenario) {
        return guide;
      }
    }
    return _mealGuides.first;
  }
}
