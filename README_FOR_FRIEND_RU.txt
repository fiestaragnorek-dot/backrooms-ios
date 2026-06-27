Что это:
Готовый исходник игры Backrooms iOS с фиксом вылета/зависания и облегчённым SceneKit-рендером под iPhone.

Что надо сделать другу на Mac:

Вариант A — собрать локально без GitHub:
1. Распаковать архив.
2. Открыть Terminal в папке backrooms-ios.
3. Установить XcodeGen, если нет:
   brew install xcodegen
4. Запустить:
   chmod +x build_local_ipa.sh
   ./build_local_ipa.sh
5. На выходе будет Backrooms.ipa.

Вариант B — через GitHub Actions:
1. Залить содержимое папки backrooms-ios в GitHub repo.
2. Открыть Actions -> Build IPA.
3. Запустить workflow или просто сделать push.
4. Скачать artifact Backrooms, внутри будет Backrooms.ipa.

Что исправлено:
- Backrooms/MazeGenerator.swift: исправлена ошибка генерации лабиринта на восток.
- Backrooms/GameViewController.swift: после кнопки ИГРАТЬ теперь реально стартует игровой цикл.
- Снижена нагрузка на iPhone: 30 FPS, без HDR/MSAA, меньше ламп, без динамических теней и прозрачных cone-мешей.

Примечание:
IPA получается unsigned. Для SideStore/AltStore её нужно подписать отдельно.
