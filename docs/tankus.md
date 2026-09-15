Ты реализуешь с нуля полноценный playable MVP игры TANKUS на Godot 4.7.x с использованием GDScript.



Это не архитектурный прототип и не набор отдельных механик. Цель — получить законченную локально-сетевую party-game, которую можно запустить на нескольких компьютерах в одной LAN, создать lobby, присоединиться, выбрать режим, сыграть полноценный матч на нескольких картах, получать способности между раундами и закончить матч победой одного игрока/команды.



Не реализовывай Steam, Steamworks, Steam P2P, аккаунты, backend, matchmaking через интернет или dedicated server. Сеть на данном этапе — только LAN через ENet, но архитектура должна позволять позднее заменить транспорт на Steam MultiplayerPeer / Steam Networking без переписывания gameplay-кода.



Используй typed GDScript везде, где это разумно.



Не останавливайся на планировании. Последовательно реализуй все этапы. После каждого этапа проект должен запускаться. Исправляй возникающие ошибки до перехода к следующему этапу.



Если какая-то мелкая деталь не описана, выбери разумное решение самостоятельно и запиши его в DESIGN\_NOTES.md. Не задавай вопросы ради мелочей.



==================================================

0\. КОНЦЕПЦИЯ ИГРЫ

==================================================



TANKUS — яркая 3D party arena game для 2–8 игроков с механикой прогрессии, вдохновлённой ROUNDS.



Игроки управляют небольшими танками на компактных многоуровневых 3D-аренах.



Основные действия любого танка:



\- движение;

\- независимое от корпуса наведение башни мышью;

\- стрельба физическими видимыми снарядами;

\- прыжок;

\- кратковременный Block;

\- ручная/автоматическая перезарядка.



У игрока одна жизнь на раунд, если способность не меняет это правило.



В FFA побеждает последний живой игрок.



В team modes побеждает команда, в которой остался хотя бы один живой игрок после уничтожения всех остальных команд.



Никаких очков за kills/damage внутри раунда нет.



Матч состоит из серии раундов.



В самом начале матча, ДО первого боя, каждый игрок получает на выбор 5 случайных карт и выбирает одну.



После каждого следующего раунда:

\- победитель FFA не получает карту;

\- остальные игроки получают выбор из 5 карт;

\- в team game все участники победившей команды не получают карту;

\- все игроки проигравших команд получают карту.



Большая часть карт stackable.

Меньшая часть — Unique.



Unique-карта больше не предлагается игроку после получения.



В рамках одного offer пять карт должны быть различными.



Точное число побед для матча не hardcode.

Используй MatchRules.target\_round\_wins.

Default = 5.



==================================================

1\. ВИЗУАЛЬНАЯ КОНЦЕПЦИЯ

==================================================



Игра должна выглядеть яркой, дружелюбной, стилизованной и немного игрушечной.



НЕ делай:

\- реалистичную военную эстетику;

\- мрачные металлические ангары;

\- тёмный gritty military shooter;

\- сложные реалистичные танки.



Нужны:

\- насыщенное голубое небо;

\- светлые материалы;

\- белый/светло-серый бетон;

\- яркие жёлтые, красные, синие, зелёные элементы;

\- трава/небольшая растительность;

\- цветные ящики;

\- выразительные взрывы;

\- яркие projectile trails;

\- лёгкий мультяшный smoke;

\- хорошо различимые цвета игроков/команд.



Если готовых моделей нет — собери симпатичный low-poly танк самостоятельно из MeshInstance3D / BoxMesh / CylinderMesh и простых материалов.



Танк должен состоять хотя бы из:

\- корпуса;

\- башни;

\- ствола;

\- условных гусениц/колёс.



Внешний вид должен быть аккуратным, а не debug geometry.



==================================================

2\. КАМЕРА И УПРАВЛЕНИЕ

==================================================



ВАЖНО: игра НЕ third-person shooter.



Камера — высокий top-down / high-angle perspective.



Примерное ощущение:

\- камера значительно выше танка;

\- угол вниз около 55–65 градусов;

\- игрок находится примерно около центральной области экрана;

\- камера НЕ находится за кормой танка;

\- камера НЕ вращается вместе с корпусом;

\- камера НЕ вращается вместе с башней;

\- вокруг игрока видно пространство во все стороны;

\- при этом вся карта целиком на экран не помещается.



Можно использовать PerspectiveCamera с умеренным FOV и слабым перспективным искажением.



Камера плавно следует за локальным танком.



Допускается небольшое camera-look-ahead в сторону курсора, но без превращения игры в third-person.



Управление:



WASD — движение относительно ориентации камеры.

Mouse — точка прицеливания.

LMB — выстрел.

R — ручная перезарядка.

Space — прыжок.

E — Block.

Esc — pause/menu.

Tab — подробный просмотр build/scoreboard.



Корпус танка постепенно ориентируется по направлению движения.



Башня вращается независимо от корпуса и всегда пытается смотреть на world-space aim position.



Курсор мыши должен отображаться в мире как небольшой прицел.



Используй raycast из камеры через mouse position.



Crosshair должен визуально выглядеть как небольшой world-space marker, а НЕ как огромный FPS crosshair в центре экрана.



Наведение должно корректно работать по:

\- полу;

\- рампам;

\- верхним платформам;

\- другим танкам;

\- вертикально расположенным объектам.



При выстреле направление вычисляй от muzzle ствола к выбранной world-space aim point.



==================================================

ЭТАП 1. СОЗДАНИЕ ПРОЕКТА И АРХИТЕКТУРА

==================================================



Создай полностью новый Godot-проект.



Рекомендуемая структура:



res://

&#x20; autoload/

&#x20;   game.gd

&#x20;   network.gd

&#x20; core/

&#x20;   match\_rules.gd

&#x20;   player\_info.gd

&#x20;   team\_info.gd

&#x20; tank/

&#x20;   tank.tscn

&#x20;   tank.gd

&#x20;   tank\_stats.gd

&#x20;   tank\_build.gd

&#x20;   tank\_visuals.gd

&#x20;   turret.gd

&#x20;   block\_component.gd

&#x20;   health\_component.gd

&#x20;   weapon\_component.gd

&#x20; projectile/

&#x20;   projectile.tscn

&#x20;   projectile.gd

&#x20; abilities/

&#x20;   card\_definition.gd

&#x20;   card\_effect.gd

&#x20;   card\_database.gd

&#x20;   effects/

&#x20; maps/

&#x20;   components/

&#x20;   map\_01/

&#x20;   map\_02/

&#x20;   map\_03/

&#x20;   map\_04/

&#x20; match/

&#x20;   match.tscn

&#x20;   match\_controller.gd

&#x20;   round\_controller.gd

&#x20;   spawn\_manager.gd

&#x20; network/

&#x20;   network\_player\_input.gd

&#x20;   lan\_discovery.gd

&#x20; lobby/

&#x20; ui/

&#x20; vfx/

&#x20; audio/

&#x20; assets/

&#x20; tests/



Раздели:

\- networking;

\- match flow;

\- tank gameplay;

\- abilities;

\- presentation.



Gameplay-код не должен напрямую зависеть от ENetMultiplayerPeer.



NetworkManager создаёт MultiplayerPeer и предоставляет абстракцию остальной игре.



Это нужно для будущего перехода на Steam transport.



Настрой InputMap.



Создай README.md:

\- запуск;

\- управление;

\- структура проекта;

\- запуск LAN игры;

\- известные ограничения.



Создай DESIGN\_NOTES.md.



==================================================

ЭТАП 2. БАЗОВЫЙ ТАНК И SINGLE-PLAYER SANDBOX

==================================================



До сети создай полностью работающий TankController.



Базовые ориентировочные параметры вынеси в Resource/config:



HP = 100

Move Speed \~= 8 m/s

Acceleration \~= 20

Jump Velocity \~= 8

Magazine Size = 4

Fire Interval \~= 0.55 sec

Reload Time \~= 1.8 sec

Projectile Damage \~= 28

Projectile Speed \~= 20–25 m/s

Block Duration \~= 0.35 sec

Block Cooldown \~= 3 sec



Это только исходные значения.

Вынеси их в данные для последующей балансировки.



Movement:

\- отзывчивый;

\- arcade, а не realistic tank simulator;

\- допускает движение назад/в стороны;

\- корпус поворачивается вслед за фактическим движением;

\- сохраняет ощущение массы;

\- работает на рампах.



Jump:

\- полноценная вертикальная мобильность;

\- позволяет перепрыгивать небольшие пропасти;

\- забираться на разные уровни карты;

\- можно стрелять и вращать башню в воздухе.



Добавь air control, но слабее ground control.



Создай grounded detection.



Смерть от падения за нижний kill plane.



==================================================

ЭТАП 3. ОРУЖИЕ, СНАРЯДЫ, BLOCK

==================================================



Снаряд — физически существующий видимый объект.



НЕ hitscan.



На MVP лучше реализовать projectile самостоятельно через CharacterBody3D / move\_and\_collide, чтобы легко контролировать:

\- collision;

\- bounce;

\- projectile speed;

\- piercing;

\- homing;

\- network authority.



Projectile должен иметь:

\- owner;

\- owner team;

\- damage;

\- speed;

\- radius;

\- lifetime;

\- bounce count;

\- pierce count;

\- knockback;

\- travelled distance;

\- effect payload.



Базовый снаряд может иметь 1 небольшой ricochet от подходящей твёрдой поверхности.

Параметр должен легко меняться.



При bounce:

velocity = velocity.bounce(collision\_normal)

и вызывается gameplay-event projectile\_bounced.



Magazine:

\- каждый выстрел расходует один патрон;

\- нельзя стрелять быстрее fire interval;

\- reload отдельный от fire rate;

\- при пустом магазине reload начинается автоматически;

\- R запускает manual reload;

\- во время reload игрок продолжает двигаться.



Block:

\- мгновенная краткая защитная способность;

\- НЕ удерживаемая;

\- активируется нажатием E;

\- полностью защищает от обычного combat damage на очень короткое время;

\- имеет cooldown;

\- Block НЕ спасает от падения в void.



При попадании снаряда в Block вызывай событие successful\_block.



По умолчанию заблокированный projectile уничтожается.



Некоторые карты позднее смогут изменить это.



Добавь VFX:

\- muzzle flash;

\- projectile trail;

\- hit spark;

\- block shield flash;

\- cartoon explosion;

\- hit feedback.



Добавь умеренный camera shake для сильных попаданий/взрывов.



==================================================

ЭТАП 4. ROUND SYSTEM И БАЗОВАЯ ARENA

==================================================



Создай первую полноценную arena.



Она должна быть:

\- компактной;

\- многоуровневой;

\- с рампами;

\- стенами;

\- пропастями;

\- укрытиями;

\- физическими ящиками.



2–8 spawn points.



Игрок не должен видеть абсолютно всю арену одной камерой.



Round flow:



PREPARE

\-> COUNTDOWN 3..2..1

\-> PLAYING

\-> ROUND\_END

\-> CARD\_DRAFT

\-> NEXT\_ROUND



У каждого игрока одна жизнь.



После death:

\- управление отключается;

\- танк красиво уничтожается;

\- игрок наблюдает оставшихся до конца раунда.



Round завершается, когда:

FFA:

alive players <= 1.



Teams:

осталась только одна команда с живыми игроками.



Добавь elapsed round timer.

Он информационный и не завершает раунд автоматически.



==================================================

ЭТАП 5. LAN MULTIPLAYER

==================================================



Реализуй LAN multiplayer через ENetMultiplayerPeer.



2–8 игроков.



Menu:



PLAY

&#x20; HOST LAN GAME

&#x20; JOIN LAN GAME



Host:

\- player name;

\- port;

\- create lobby.



Join:

\- player name;

\- IP;

\- port.



Default gameplay port, например 7000.



Если возможно без чрезмерного усложнения — добавь LAN discovery через UDP broadcast:

\- кнопка Discover LAN Games;

\- прямой IP всегда остаётся fallback.



Lobby должен показывать:

\- имя;

\- connection status;

\- team;

\- ready status.



Host может выбирать:

\- map;

\- FFA / Teams;

\- number of teams для Teams: 2–4;

\- target round wins.



Поддержи в том числе:

\- 1v1;

\- 2v2;

\- 3v3;

\- 4v4;

\- 2v2v2;

\- 2v2v2v2;

\- асимметричные команды, если host их специально создал.



Host нажимает Start только когда минимум 2 игрока.



==================================================

ЭТАП 6. SERVER-AUTHORITATIVE NETWORK GAMEPLAY

==================================================



Host является game authority.



Host определяет:

\- transforms;

\- HP;

\- damage;

\- death;

\- projectile spawn;

\- projectile hit;

\- physics props;

\- abilities;

\- card offers;

\- card validation;

\- round state;

\- scores;

\- victory.



Клиент НЕ должен отправлять:

"я нанёс 30 damage".



Клиент отправляет input/intention:

\- move vector;

\- aim;

\- shoot pressed;

\- reload;

\- jump;

\- block.



Host валидирует и выполняет действие.



LAN latency небольшая, поэтому сначала используй простой server authoritative movement.



Клиент может немедленно локально:

\- двигать cursor;

\- поворачивать локальную turret визуально;

\- проигрывать input feedback.



Но истинное состояние принадлежит host.



Используй MultiplayerSpawner / MultiplayerSynchronizer либо собственную понятную state replication систему.



RigidBody props:

\- физика рассчитывается host;

\- клиенты получают transform/velocity;

\- НЕ запускай независимую competing physics simulation на каждом peer.



Добавь interpolation удалённых игроков.



Не пытайся делать deterministic lockstep.



Если host disconnect:

\- корректно завершить match;

\- остальные получают сообщение;

\- возврат в main menu.



Host migration не нужен.



==================================================

ЭТАП 7. DATA-DRIVEN BUILD / CARD SYSTEM

==================================================



Это центральная механика TANKUS.



Создай CardDefinition Resource.



Пример полей:



id

display\_name

description

category

icon

unique

max\_stacks

tags

effect\_script / effect\_resource



Categories:



SHOT

BLOCK

JUMP

GENERAL



TankBuild хранит:

card\_id -> stack\_count



Порядок первого получения карты тоже сохранить для UI.



НЕ делай giant switch на 50 карт.



Создай расширяемую effect architecture.



Поддержи gameplay events примерно такого типа:



on\_shot

on\_projectile\_spawned

on\_projectile\_hit

on\_projectile\_bounce

on\_reload\_started

on\_reload\_completed

on\_block\_started

on\_successful\_block

on\_jump

on\_land

on\_damage\_taken

on\_damage\_dealt

on\_kill

on\_death

on\_revive



Derived tank stats должны пересчитываться из:

base stats + modifiers



Не мутируй базовые значения бесконечным накоплением floating point операций.



Stackable cards должны нормально суммироваться/умножаться.



Добавь safeguards/clamps против отрицательного reload time, нулевых cooldown и т.п.



==================================================

ЭТАП 8. ПЕРВЫЙ ПУЛ СПОСОБНОСТЕЙ

==================================================



Реализуй минимум следующие способности ПОЛНОСТЬЮ.



Не создавай stub-карты, которые отображаются, но ничего не делают.



SHOT:



1\. Heavy Shell \[stackable]

Больше damage, немного меньше projectile speed.



2\. Rapid Fire \[stackable]

Меньше fire interval, немного меньше damage.



3\. Fastball \[stackable]

Больше projectile speed.



4\. Big Magazine \[stackable]

+1 magazine capacity, немного увеличивает reload time.



5\. Quick Reload \[stackable]

Снижает reload time.



6\. Bouncy \[stackable]

+1 projectile bounce.



7\. Ricochet Power \[stackable]

После каждого bounce projectile получает дополнительный damage и speed.



8\. Poison \[stackable]

Попадание наносит DoT.

Следующие stacks увеличивают силу/длительность.



9\. Explosive Shell \[stackable]

Hit вызывает небольшой AoE explosion.

Stacks увеличивают radius/effect.



10\. Big Shot \[stackable]

Projectile становится крупнее и немного сильнее, но медленнее.



11\. Knockout \[stackable]

Сильнее knockback танков и физических props.



12\. Piercing \[stackable]

+1 enemy penetration.



13\. Homing \[stackable]

Слабое наведение projectile на ближайшего подходящего enemy.

Stacks усиливают steering.



14\. Last Round \[stackable]

Последний патрон магазина наносит значительно больше damage.



15\. First Round \[stackable]

Первый shot после полной reload быстрее и сильнее.



16\. Recoil \[stackable]

Выстрел сильнее толкает собственный tank назад и немного повышает damage.

Должен позволять использовать пушку для mobility.



17\. Sniper Shell \[stackable]

Damage увеличивается в зависимости от пройденной projectile дистанции.



18\. Shotgun \[unique]

Один shot создаёт несколько более слабых projectiles с spread.



BLOCK:



19\. Quick Guard \[stackable]

Снижает Block cooldown.



20\. Long Block \[stackable]

Увеличивает Block duration, слегка увеличивая cooldown.



21\. Blink \[stackable]

При Block tank телепортируется по направлению aim.

Stack увеличивает distance.



Проверяй collision, нельзя teleport внутрь стены.



22\. Shockwave \[stackable]

Block создаёт radial force вокруг tank.



23\. Reload Block \[stackable]

Successful Block ускоряет текущую reload.



24\. Ammo Shield \[stackable]

Successful Block восстанавливает ammo.



25\. Counter Shot \[stackable]

Successful Block автоматически выпускает бесплатный shot в текущем aim direction.



26\. Reflect \[unique]

Projectile, попавший в Block, отражается и переходит во владение blocking player.



27\. Perfect Guard \[unique]

Если попадание произошло в первые \~20–25% Block window, cooldown практически/полностью сбрасывается.



JUMP:



28\. High Jump \[stackable]

Повышает jump height.



29\. Air Control \[stackable]

Повышает управление в воздухе.



30\. Ground Slam \[stackable]

После достаточно высокого падения landing создаёт shockwave/damage.



31\. Jump Mine \[stackable]

При jump в точке старта остаётся небольшая mine.

У mine разумный lifetime.



32\. Death From Above \[stackable]

Projectiles, выпущенные в воздухе, получают bonus damage.



33\. Double Jump \[unique]

Один дополнительный jump в воздухе.



GENERAL:



34\. Tankier \[stackable]

+max HP.



35\. Lightweight \[stackable]

Больше speed, меньше mass/knockback resistance.



36\. Heavyweight \[stackable]

Больше knockback resistance, немного хуже acceleration.



37\. Adrenaline \[stackable]

При низком HP speed увеличивается.



38\. Glass Cannon \[stackable]

Меньше max HP, значительно больше damage.



39\. Regeneration \[stackable]

После нескольких секунд без damage постепенно восстанавливает HP.



40\. Vampire \[stackable]

Небольшая часть нанесённого enemy damage возвращается как HP.



41\. Road Rage \[stackable]

Сильное столкновение tank с enemy наносит damage в зависимости от relative speed.



42\. Tiny Tank \[stackable]

Физический tank становится немного меньше и быстрее, но получает штраф HP.



Несколько stacks должны действительно создавать смешного маленького tank.



43\. Big Tank \[stackable]

Tank крупнее, тяжелее и прочнее, но немного медленнее.



44\. Comeback \[stackable]

В team mode, когда игрок остаётся последним живым членом своей команды, получает временные buffs:

speed

reload

block cooldown.



45\. Phoenix \[unique]

Один раз за round смерть отменяется.

Через короткую задержку tank возвращается примерно с 50% HP.

После revive дать короткую spawn protection.



Большая часть pool специально stackable.



==================================================

ЭТАП 9. CARD DRAFT И MATCH PROGRESSION

==================================================



Перед первым round:

ВСЕ игроки выбирают 1 из 5 карт.



После каждого round:

только проигравшие выбирают карту.



Offer генерируется HOST.



У каждого выбирающего игрока собственный random offer.



Unique card не должна предлагаться владельцу повторно.



Внутри одного offer нет duplicate choices.



Добавь card draft UI:



\- пять крупных cards;

\- icon;

\- name;

\- description;

\- категория;

\- stack indicator, если карта уже имеется;

\- keyboard 1–5 или mouse click.



Draft timer примерно 20 секунд.



Если timer закончился:

host автоматически выбирает random offered card.



После выбора показывай короткую красивую animation:

card -> уменьшается -> улетает к build icons.



Пока проигравшие выбирают карты:

победители видят intermission screen и свои builds.



Все build data после выбора синхронизируется всем игрокам.



==================================================

ЭТАП 10. UI / HUD

==================================================



HUD должен быть чистым и минимальным.



TOP LEFT:

текущий build игрока.



НЕ делай большой внешний container.



Показывай только небольшие квадратные ability icons.



Например:



\[Poison ×2] \[Bouncy ×3] \[Blink] \[Tankier ×2]



Но визуально:

\- только icon;

\- маленький ×2/×3;

\- никаких длинных названий.



Порядок — порядок первого получения карты.



BOTTOM LEFT:

HP

health bar

число HP.



BOTTOM RIGHT:

Ammo

например 3 / 6.



Если reload:

показать reload progress / remaining time.



Рядом:

BLOCK.



Иконка Block ОБЯЗАТЕЛЬНО должна быть ЩИТОМ.

Не кубом и не коробкой.



Block indicator:

\- яркий shield, когда ready;

\- circular cooldown;

\- remaining seconds;

\- \[E].



Jump постоянно в HUD НЕ показывать.



CENTER / WORLD:

небольшой mouse crosshair.



TOP CENTER:

match score / round wins + elapsed round timer.



Для 2-team mode:

BLUE 2 | 01:14 | RED 3



Для 3–4 teams:

покажи компактный ряд team score chips.



FFA:

покажи компактные player win counters / лидеров так, чтобы интерфейс не занимал половину экрана.



Score означает только число выигранных rounds.



==================================================

ЭТАП 11. WORLD-SPACE INFORMATION НАД ДРУГИМИ ТАНКАМИ

==================================================



Рядом с другими видимыми танками игрок должен видеть их текущее боевое состояние.



Над enemy / ally:



PlayerName

HP bar

ammo state

block state



Ammo:

используй маленькие bullet pips, если magazine небольшой.



Пример:

● ● ● ○



Для больших magazines допускается компактное число:

7/12.



Во время reload:

\- ammo визуально гаснет;

\- появляется очень маленький reload progress indicator.



Block:

маленький shield icon.



Когда ready:

щит яркий.



Когда cooldown:

щит приглушён и имеет небольшой radial progress / число.



Эта информация должна позволять игроку понять:

\- у enemy закончились патроны;

\- enemy сейчас reload;

\- enemy Block ещё не восстановился;

\- сейчас хороший момент для атаки.



У СВОЕГО локального tank НЕ дублируй overhead ammo/block, потому что эта информация уже находится в HUD.



Enemy information не должна показываться сквозь стены.



Если tank визуально полностью occluded geometry с позиции камеры — скрывай его nameplate/status.



==================================================

ЭТАП 12. MAPS

==================================================



Сделай минимум 4 законченные карты.



Общий стиль:

яркие компактные stylized floating arenas.



MAP 1 — SKY COURTYARD



Базовая многоуровневая arena:

\- центральная площадка;

\- ramps;

\- elevated areas;

\- gaps;

\- несколько crates;

\- стены для ricochets.



MAP 2 — ICEWORKS



Особенность:

часть пола ледяная.



Ice снижает friction / делает управление инерционнее.



Не делай всю карту ледяной.



MAP 3 — PENDULUM YARD



Несколько больших кубов подвешены на тросах/constraints.



Их можно:

\- толкать tank;

\- раскачивать projectiles;

\- использовать как временное укрытие.



Они НЕ должны полностью улетать с карты.



Добавь физические crates.



MAP 4 — SHIFT



Карта содержит 1–2 moving platforms.



Не превращай всю карту в moving obstacle course.



Движущиеся элементы — специальная особенность, а не постоянный хаос.



У всех карт:

\- 8 spawn points;

\- spawn selection старается разводить игроков;

\- fall kill volumes;

\- достаточное количество cover;

\- vertical routes;

\- минимум тупиков;

\- пространство для прыжков;

\- стены, от которых полезны ricochets.



==================================================

ЭТАП 13. TEAM / FFA LOGIC И ЗАВЕРШЕНИЕ MATCH

==================================================



FFA:

каждый против каждого.



Teams:

friendly\_fire = false по умолчанию.



Вынеси friendly fire в MatchRules, чтобы позднее его можно было включить.



Союзники могут физически сталкиваться, но collision не должен позволять им бесконечно grief-блокировать друг друга.



Round winner получает +1 round win.



При достижении target\_round\_wins:

match завершается.



Покажи:

\- winner;

\- final score;

\- player builds;

\- Rematch;

\- Return to Lobby.



Rematch сбрасывает:

\- builds;

\- scores;

\- HP;

\- round state;



но сохраняет lobby игроков.



==================================================

ЭТАП 14. GAME FEEL / POLISH

==================================================



Не оставляй MVP визуально похожим на debug prototype.



Добавь:



\- приятную tank acceleration/deceleration;

\- небольшой suspension-like visual bob;

\- turret smoothing;

\- muzzle flash;

\- tracer/projectile trails;

\- landing dust;

\- jump effect;

\- hit flash;

\- block pulse;

\- poison VFX;

\- explosion VFX;

\- Phoenix revive effect;

\- Ground Slam shockwave;

\- Blink trail;

\- death explosion;

\- debris, не влияющий на network gameplay;

\- мягкий camera shake;

\- небольшие UI animations;

\- countdown;

\- round victory banner;

\- card acquisition animation.



Не делай эффекты настолько огромными, чтобы 8 игроков превращали экран в нечитаемую кашу.



Player readability важнее spectacle.



При возможности добавь простые звуки:

\- shot;

\- hit;

\- explosion;

\- reload;

\- block;

\- successful block;

\- jump;

\- death;

\- card select;

\- round win.



Используй только собственные/CC0/free redistributable assets.

Если скачиваешь внешние assets, сохрани источник и лицензию в CREDITS.md.



Если внешних assets нет, gameplay не должен зависеть от них.



==================================================

ЭТАП 15. ТЕСТИРОВАНИЕ И ФИНАЛЬНАЯ ДОВОДКА

==================================================



Обязательно протестируй:



1 player sandbox/debug

2 players LAN/localhost

4 clients localhost, если позволяет окружение

host + remote clients

FFA

2v2

3 teams

death by projectile

death by falling

simultaneous deaths

host winning

client winning

player disconnect

reload synchronization

block synchronization

projectile bounce

physical props

card draft

stackable abilities

unique cards

Phoenix

end of match

rematch



Проверь edge cases:



\- два последних игрока умирают почти одновременно;

\- Phoenix срабатывает у потенциального последнего alive player;

\- projectile отражается Reflect и убивает исходного shooter;

\- player disconnect во время draft;

\- player disconnect во время round;

\- все проигравшие выбирают карты с разной скоростью;

\- player умирает от собственного explosive/recoil interaction;

\- team остаётся без живых игроков;

\- large magazine UI;

\- очень много stacks;

\- Blink около стены/края карты;

\- moving platform + jumping tank;

\- hanging physics object network sync.



Добавь developer debug overlay, включаемый F3:

\- FPS;

\- ping;

\- peer id;

\- host/client;

\- round state;

\- current map;

\- number of active projectiles.



Добавь dev console/debug shortcuts только в debug builds, например:

\- kill local player;

\- give random card;

\- start next round;

\- show builds.



Создай удобный способ запуска нескольких экземпляров на одной машине.



Например документируй команды:



godot --path . --editor



и способы запуска host/client через command line arguments:



\--host

\--join=127.0.0.1

\--player-name=Player2



Если удобно, реализуй эти launch arguments.



==================================================

КРИТЕРИИ ГОТОВОГО MVP

==================================================



Работа НЕ считается законченной, если существует только:

\- одна sandbox-сцена;

\- один tank;

\- mocked multiplayer;

\- UI без настоящей логики;

\- карты без round system;

\- ability cards, которые ничего не делают.



Готовый результат должен позволять:



1\. Запустить игру.

2\. Создать LAN lobby.

3\. Второму–восьмому игроку подключиться.

4\. Выбрать FFA или teams.

5\. Выбрать карту.

6\. Начать match.

7\. Каждому выбрать стартовую карту из пяти.

8\. Играть полноценный round.

9\. Стрелять, прыгать, использовать Block.

10\. Видеть ammo/reload/block врагов.

11\. Получать damage и погибать.

12\. Закончить round последним игроком/командой.

13\. Проигравшим выбрать новые cards.

14\. Увидеть, как build реально изменил tank.

15\. Играть следующие rounds.

16\. Увидеть текущий build в HUD.

17\. Набрать target round wins.

18\. Получить экран победителя.

19\. Запустить Rematch.

20\. Сыграть на нескольких разных maps.



В конце:



\- запусти проект;

\- исправь parser/runtime errors;

\- устрани очевидные networking bugs;

\- проверь отсутствие missing resources;

\- обнови README.md;

\- обнови DESIGN\_NOTES.md;

\- создай IMPLEMENTATION\_STATUS.md с кратким перечнем реально реализованных систем и известных ограничений.



Не заканчивай работу сообщением вроде:

"Architecture is ready, remaining gameplay can be implemented later."



Нужна именно законченная playable vertical slice / MVP TANKUS.

