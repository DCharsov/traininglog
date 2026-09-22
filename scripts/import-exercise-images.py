import json,pathlib,urllib.request,concurrent.futures
# Explicit matches; differences between the reference and workout are disclosed in the guide.
rows=[
('Incline Pronated DB Bench Press','Жим гантелей на наклонной скамье','Incline_Dumbbell_Press','Ляг на наклонную скамью, поставь стопы на пол. Выжми гантели вверх и плавно опусти к груди.',''),
('Flat Pronated DB Bench Press','Жим гантелей лёжа','Dumbbell_Bench_Press','Ляг на горизонтальную скамью, устойчиво поставь стопы. Выжми гантели над грудью и опусти под контролем.',''),
('Hammer Strength Decline Chest Press','Жим на нижнюю часть груди в Hammer Strength','Leverage_Decline_Chest_Press','Прижми спину к опоре и возьми рукояти. Выжми их вперёд, затем плавно верни.','На фото рычажный тренажёр: его конструкция может отличаться от твоего Hammer Strength.'),
('Pec Deck','Сведение рук в тренажёре «бабочка»','Butterfly','Прижми спину к опоре. Сведи руки перед грудью и плавно разведи, сохраняя контроль.','Положение рук зависит от конструкции тренажёра.'),
('Push Ups','Отжимания от пола','Pushups','Упрись ладонями в пол, удерживай тело прямым. Опусти грудь к полу и оттолкнись вверх.',''),
('Lat Pulldown Lean Away Medium …','Тяга верхнего блока с небольшим отклонением','Wide-Grip_Lat_Pulldown','Зафиксируй бёдра под валиками. Тяни рукоять к верхней части груди, затем плавно выпрями руки без раскачки.','На фото широкий хват. В исходной программе указан средний хват, полное название обрезано: точный вариант уточни.'),
('Hammer Strength Overhand Row','Тяга в Hammer Strength хватом сверху','Leverage_Iso_Row','Упрись грудью в подушку. Тяни рукояти к корпусу и плавно возвращай, не отрывая грудь от опоры.','Фото показывает похожую рычажную тягу; рукояти и хват могут отличаться.'),
('Chest Supported Incline Neut…','Тяга гантелей с упором грудью, нейтральный хват','Dumbbell_Incline_Row','Ляг грудью на наклонную скамью, ладони обращены друг к другу. Подтяни гантели к бокам корпуса и опусти.','В источнике название обрезано; показан вариант тяги с опорой грудью.'),
('DB Pullover','Пуловер с гантелью','Bent-Arm_Dumbbell_Pullover','Держи гантель двумя руками над грудью. Слегка согни локти, плавно уведи гантель за голову и верни.','На фото опора поперёк скамьи. В твоём источнике положение на скамье может отличаться.'),
('Seated Rear Delt Flys','Разведения гантелей в наклоне сидя','Seated_Bent-Over_Rear_Delt_Raise','Сядь и наклони корпус вперёд. Разведи слегка согнутые руки в стороны, затем опусти без рывка.',''),
('Barbell Deadlift','Становая тяга со штангой','Barbell_Deadlift','Подойди к грифу, отведи таз назад и возьмись за штангу. Встань, держа гриф близко к ногам; опусти с контролем.',''),
('Cybex Medium Stance Leg Press','Жим ногами в Cybex, средняя постановка','Leg_Press','Прижми таз и спину к опоре, поставь стопы на платформу. Согни колени в доступной амплитуде, затем выжми платформу.','Показан обычный жим ногами: конструкция и настройки Cybex могут отличаться.'),
('DB Walking Lunges','Выпады с гантелями в ходьбе','Dumbbell_Lunges','Держи гантели по бокам. Шагни вперёд, опустись в выпад и поднимись, затем сделай шаг другой ногой.','На фото выпад на месте; в программе — последовательные шаги вперёд.'),
('Lying Leg Curl - Neutral (Dorsi…','Сгибание ног лёжа в тренажёре','Lying_Leg_Curls','Ляг на живот, размести валик над пятками. Согни колени, приблизив пятки к ягодицам, затем плавно разогни.','Название в источнике обрезано: точное положение стоп не подтверждено.'),
('DB RDL','Румынская тяга с гантелями','Stiff-Legged_Dumbbell_Deadlift','Слегка согни колени и отводи таз назад, опуская гантели вдоль ног. Вернись в стойку, разгибая таз.','На фото близкий вариант тяги на почти прямых ногах. В румынской тяге колени слегка согнуты; касаться пола не требуется.'),
('Standing Calf Raise Machine Me…','Подъём на носки стоя в тренажёре','Standing_Calf_Raises','Поставь переднюю часть стоп на платформу. Поднимись на носки и плавно опусти пятки, удерживая корпус устойчиво.','Название в источнике обрезано; точная постановка стоп не подтверждена.'),
('Flat Bench DB Skull Crushers','Французский жим с гантелями лёжа','Lying_Dumbbell_Tricep_Extension','Ляг на скамью и подними гантели. Сгибая локти, опусти гантели по сторонам головы, затем разогни руки.',''),
('Incline Supinated DB Curls','Сгибание рук с гантелями на наклонной скамье','Incline_Dumbbell_Curl','Сядь с опорой спины, руки опусти, ладони направь вперёд. Согни локти и плавно опусти гантели.',''),
('Cable Rope French Press','Разгибание рук с канатом из-за головы','Cable_Rope_Overhead_Triceps_Extension','Встань спиной к блоку, держи канат за головой. Разогни локти, затем верни руки, сохраняя корпус устойчивым.',''),
('Cable Rope Tricep Pushdowns','Разгибание рук с канатом вниз','Triceps_Pushdown_-_Rope_Attachment','Возьми канат верхнего блока, локти держи у корпуса. Разогни руки вниз, затем плавно согни.',''),
('Standing DB Hammer Curls','Сгибание рук «молоток» стоя','Hammer_Curls','Держи гантели по бокам, ладонями к корпусу. Согни локти без раскачки и плавно опусти гантели.',''),
('Cable Rope Hammer Curl','Сгибание рук «молоток» с канатом','Cable_Hammer_Curls_-_Rope_Attachment','Возьми канат нижнего блока ладонями друг к другу. Согни локти и плавно опусти рукоять.',''),
('High Pulley Rope Cable Crunch','Скручивания стоя с канатом верхнего блока','Standing_Rope_Crunch','Держи канат около головы. Сократи мышцы живота, округляя верх корпуса, затем плавно вернись.',''),
('Seated DB Shoulder Press','Жим гантелей сидя','Dumbbell_Shoulder_Press','Сядь с опорой спины, держи гантели у плеч. Выжми их вверх и плавно опусти.',''),
('Cable Rope Upright Row','Тяга каната к подбородку','Upright_Cable_Row','Возьми канат нижнего блока. Подними локти в стороны, ведя рукоять вдоль корпуса, затем опусти без рывка.','На фото прямая рукоять; в твоей программе используется канат. Высоту подъёма выбирай по комфортной амплитуде.'),
('Standing DB Side Lateral Raises','Подъём гантелей через стороны стоя','Side_Lateral_Raise','Слегка согни локти. Подними гантели через стороны примерно до уровня плеч, затем плавно опусти.',''),
('Cable Rope Face Pulls','Тяга каната к лицу','Face_Pull','Возьми канат примерно на уровне лица. Тяни его к лицу, разводя локти и кисти, затем плавно выпрями руки.',''),
('Band Pull Aparts','Разведение рук с резинкой','Band_Pull_Apart','Держи резинку перед грудью. Разведи руки в стороны, растягивая её, затем плавно верни.',''),
]
root=pathlib.Path('apps/web/src');assets=root/'assets/exercises';assets.mkdir(parents=True,exist_ok=True)
commit='a859101d633a01c4a1a920d6a8ce41dabba0705f'
source_cache=pathlib.Path('deploy/exercise-source');source_cache.mkdir(parents=True,exist_ok=True)
repo=f'https://raw.githubusercontent.com/yuhonas/free-exercise-db/{commit}/'
for remote,local in [('dist/exercises.json','exercises.json'),('LICENSE.md','LICENSE.md')]:
 source_cache.joinpath(local).write_bytes(urllib.request.urlopen(repo+remote,timeout=30).read())
data={e['id']:e for e in json.loads(source_cache.joinpath('exercises.json').read_text(encoding='utf-8'))}
base=repo+'exercises/'
guides=[];jobs=[]
for english,ru,source,cue,note in rows:
 e=data[source];images=[]
 for i,path in enumerate(e['images'][:2]):
  filename=f'{source}-{i}.jpg';images.append(filename);jobs.append((base+path,assets/filename))
 guides.append(dict(english=english,ru=ru,source=source,cue=cue,note=note,images=images))
def fetch(job):
 url,path=job;path.write_bytes(urllib.request.urlopen(url,timeout=30).read())
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(fetch,jobs))
(root/'exerciseGuides.json').write_text(json.dumps(guides,ensure_ascii=False,indent=2),encoding='utf-8')
pathlib.Path('docs/exercise-images-license.md').write_text('# Фотографии упражнений\n\nИсточник: https://github.com/yuhonas/free-exercise-db\nCommit: '+commit+'\n\nСопоставления и различия: apps/web/src/exerciseGuides.json. Имена локальных JPEG содержат ID исходного упражнения. Файлы загружены без изменений. Короткие русские подсказки составлены для интерфейса; это не полный разбор техники.\n\n'+pathlib.Path('deploy/exercise-source/LICENSE.md').read_text(encoding='utf-8'),encoding='utf-8')
print('Downloaded',len(jobs),'photos;',sum(p.stat().st_size for p in assets.glob('*.jpg')),'bytes;',commit)
