#include "Flags.h"

#ifndef PROFILE_DATA
#define PROFILE_DATA

/***************************************************************
 * Declarations used to construct the rp2graph data structure. *
 ***************************************************************/
#define readWord(V, F) {if (((V) = getw(F)) == EOF) { \
			  printf("Error in reading input file\n"); \
			  exit(-1); \
		        }}\


#define MAX_REGIONS_TO_PROFILE 2000000    /* maximal number of region variables in
                                            region-annotated lambda term (the source) */
#define MAX_ALLOCATION_POINTS 200000     /* maximal number of allocation points in the
					    region annotated lambda term. */

typedef struct objectList {
  int atId;                /* Allocation point identifier. */
  int size;                /* Size of object in bytes. */
  int numberOfInstances;   /* Number of instances of an object at an allocation point. */
  struct objectList *nObj; /* Pointer to next object. */
} ObjectList;

typedef struct regionList {
  int regionId;                /* id of region. */
  int numberOfInstances;       /* number of instances of the region(variable) */
  int used;                    /* number of used words in the region.         */
  int waste;                   /* number of not used words in the region.     */
  int noObj;                   /* number of objects with different program points. */
  int infinite;                /* is region finite of infinite. */
  ObjectList *fObj;            /* Pointer to first object. */
  struct regionList * nRegion; /* Pointer to next region. */
} RegionList;

typedef struct tickList {
  RegionList * fRegion;    /* Pointer to first region. */
  int stackUse;            /* Number of words used on the stack excl. regions. */
  int regionDescUse;       /* Number of words used to infinite regiondescriptors on the stack. */
  unsigned int time;       /* Number of seconds after start (excl. profiling.) */
  struct tickList * nTick; /* Pointer to data for the next tick. */
} TickList;

extern TickList * firstTick;           /* Pointer to data for the first tick. */
extern TickList * lastTick;            /* Pointer to data for the last tick. */
extern RegionList * regionHashTable[]; /* Used as hash table into a region list. */
extern ObjectList * objectHashTable[]; /* Used as hash table into an object list. */

/*extern int profTab[];*/ /* Table containing statistics about regions. */
#define NoOfPages 0
#define MaxNoOfPages 1
#define NoOfInstances 2
#define MaxNoOfInstances 3
#define AllocNow 4
#define MaxAlloc 5

extern int maxRegions;    /* max. number of allocated words in regions. */
extern int maxInstances;  /* max. number of instances.       */

/*--------------------------------------------*
 * External function declarations.            *
 *--------------------------------------------*/
void inputProfile(void);
void PrintProfile(void);
void PrintRegion(int region);
void PrintSomeStat(void);
void MakeRegionProfile(void);
void MakeStackProfile(void);
void MakeRegionInstanceProfile(void);
void MakeObjectProfile(int region);
void FindProgramPoint(int pPoint);

#endif /* PROFILE_DATA */
