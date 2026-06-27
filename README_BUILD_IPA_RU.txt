Backrooms iOS — fixed build package

Что исправлено:
1) Backrooms/MazeGenerator.swift — исправлено движение на восток в генераторе лабиринта.
2) Backrooms/GameViewController.swift — после кнопки ИГРАТЬ теперь выключается inMenu.
3) Снижена нагрузка SceneKit под iPhone: 30 FPS, без MSAA/HDR, меньше ламп, без динамических теней и прозрачных cone-мешей.

Как собрать IPA через GitHub Actions:
1. Создать/открыть репозиторий GitHub.
2. Загрузить содержимое этого архива в корень репозитория.
3. Открыть Actions -> Build IPA -> Run workflow.
4. После успеха скачать artifact Backrooms.
5. Внутри будет Backrooms.ipa.

Если есть git на компьютере:
 git clone <repo-url>
 # скопировать файлы из архива поверх репозитория
 git add .
 git commit -m "fix: stabilize iPhone build"
 git push

Workflow уже лежит в .github/workflows/build.yml.
