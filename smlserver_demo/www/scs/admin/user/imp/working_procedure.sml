val user_id = ScsLogin.auth_roles [ScsRole.SiteAdm, ScsRole.ScsPersonAdm]

val title = ScsDict.s [(ScsLang.en,`Central Personnel Register - Working Procedure (Danish only)`),
		       (ScsLang.da,`Centralt Person Register - Vejledning`)]

val content = `

  Design og implementation af det centrale personregister (matrikel)
  er dokumenteret <a href="/ucs/doc/scs/scs_users.html">separat.</a><p>

  Denne vejledning fokuserer p� de arbejdsopgaver, som skal
  gennemf�res for at det centrale personregister (matrikel) er
  opdateret.<p>

  Vi har tre eksterne kilder: 

  <ul>
    <li> Login fra IT-afdelingen
    <li> Personoplysninger p� studerende fra HSAS
    <li> Personoplysninger p� personer der er tilknyttet IT-C
    (personfortegnelsen)
  </ul>

  Vi gemmer kun simpel information om hver person i det centrale
  personregister, dvs. navn, cpr, email og url til
  hjemmeside. Derudover kan vi i det centrale personregister se, hvor
  de enkelte personoplysninger kommer fra. En enkelt person i det
  centrale personregister kan stamme fra mere end en ekstern kilde. En
  ansat vil eksempelvis stamme fra personfortegnelsen samt login fra
  IT-afdeligen. En ansat der ogs� er studerende vil stamme fra alle
  tre eksterne kilder.<p>

  Data fra de eksterne kilder overf�res til det centrale
  personregister en gang i d�gnet. Vi har opstillet nogle regler, som
  g�r, at det centrale personregister for langt de fleste personer kan
  opdateres automatisk (cirka 95%). Til de sidste 5% m� vi manuelt
  tage stilling til, om en person eksempelvis findes i forvejen eller
  skal oprettes som en ny person. En post indl�ses automatisk s�fremt
  et af f�lgende er opfyldt:

  <ol> 

  <li> der er et eksakt match i personfortegnelsen, dvs. enten at 1)
  posten har tidligere v�ret indl�st eller 2) at der findes en person
  med samme email og normaliseret navn eller 3) at der findes en
  person med samme cpr-nummer. Hvis en person har navnet "Hans Peter
  Matiesen", s� er det normaliserede navn "hansmatiesen", dvs. det
  f�rste fornavn samt efternavn sammensat med sm� bogstaver.

  <li> hvis der ikke er et eksakt match, s� oprettes personen p� ny
  s�fremt, at der ikke allerede findes en person med et tilsvarende
  normaliseret navn.

  </ol>

  Vi har udviklet nogle sk�rmbilleder, som kan anvendes til at
  inds�tte de personer, der kr�ver manuel stillingtagen.<p>

  Sk�rmbilledet <a href="imp_form.sml">Centralt Person Register</a>
  viser hvilke poster i de tre eksterne kilder, som ikke er blevet
  indl�st. Ved at klikke p� linket <b>automatisk indl�sning</b> vil
  systemet fors�ge at indl�se posterne efter de regler der er
  beskrevet ovenfor.<p>

  For hver post der ikke er indl�st kan vi ud over data p� personen
  (navn, cpr og email) se hvorn�r posten sidst er fors�gt indl�st
  <b>Sidste Import</b> samt om der findes et <b>eksakt match</b> i det
  centrale personregister. Der findes et eksakt match s�fremt at
  systemet kan finde en og kun en person i det centrale
  personregister, som matcher udfra de opstillede regler beskrevet
  ovenfor. Hvis dette er tilf�ldet vil posten blive indl�st n�ste gang
  man klikker <b>automatisk indl�sning</b> eller klikker p� linket
  <b>import</b>, som vil st� i kolonnen <b>Eksakt Match</b>.<p>

  S�fremt posten ikke kan indl�ses automatisk kan vi v�lge at se mere
  information om posten (kolonne <b>Mere Info</b>). P� sk�rmbilledet
  <b>Mere Info</b> kan vi v�lge 1) at slette posten (s�ledes at den
  ikke vil blive en del af det centrale personregister), eller 2) at
  oprette personen som ny eller 3) at indl�se personen som en der
  allerede eksisterer med samme normaliseret navn.

  <h2>Check for Inkonsistente Data</h2>

  Det er muligt at sammenholde personoplysningerne fra det centrale
  personregister med de eksterne kilder. Ved at klikke linket <a
  href="chk_inconsistencies.sml">check for inkonsistente data</a> f�r
  vi tre tabeller for hver ekstern kilde. Tabellerne viser 

  <ol>

    <li> personer med cpr-nummer i det centrale personregister, som
    ikke matcher det cpr-nummer som findes i den eksterne kilde.

    <li> personer i det centrale personregister med navne, som er
    forskellige fra de der findes i de eksterne kilder
    
    <li> personer i det centrale personregister med emails, som er
    forskellige fra de der findes i de eksterne kilder

  </ol>

    Fejl skal rettes i de eksterne kilder hvorefter det centrale
    personregister efterf�lgende vil blive opdateret.<p>

    Du er altid velkommen til at kontakte <a
    href="mailto:^(ScsUserImp.service_adm_email)">^(ScsUserImp.service_adm_email)</a>,
    for hj�lp eller ved rapportering af fejl.

`

val _ = ScsUserImp.returnPg title
  (`<h1>^title</h1> 
   ` ^^ content)
