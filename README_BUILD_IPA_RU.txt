Backrooms iOS — v6 crashfix hash + latestlog sync

По присланному latestlog видно:
- AppDelegate стартует;
- viewDidLoad стартует;
- ресурсы загрузились;
- setupScene завершился;
- до buildLevel/log дальше приложение не дошло.

Причина найдена: в процедурном hash01 был Int32(...) от большого/отрицательного значения.
При streaming 3x3 первые комнаты имеют координаты -1,-1 / 0,-1 и т.п.; Int32(...) на iOS может trap-нуть, из-за чего был чёрный экран и вылет.

Что исправлено в v6:
1) hash01 переписан на UInt64 без Int32 trap.
2) latestlog теперь пишет синхронно, чтобы последняя строка точно успевала сохраниться перед вылетом.
3) Добавлены подробные строки:
   - buildLevel streaming start/done;
   - rebuildActiveRooms start/done;
   - buildRoom start/done;
   - kind/special комнаты.
4) Сохранены v5 фичи:
   - streaming 3x3;
   - большие пустые комнаты;
   - свалки мебели;
   - горки/скаты;
   - фейковый верхний лабиринт без потолка;
   - прямые и спиральные лестницы;
   - latestlog.txt и кнопка LATESTLOG.

Если снова вылетит — пришли новый latestlog.txt.
