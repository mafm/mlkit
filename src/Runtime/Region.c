/*----------------------------------------------------------------*
 *                        Regions                                 *
 *----------------------------------------------------------------*/
#include "Flags.h"
#include "Region.h"
#include "Math.h"
#include "Profiling.h"
#include "GC.h"
#include "CommandLine.h"

#ifdef THREADS
#include "/usr/share/aolserver/include/ns.h"
extern Ns_Mutex freelistMutex;
#define FREELIST_MUTEX_LOCK     Ns_LockMutex(&freelistMutex);
#define FREELIST_MUTEX_UNLOCK   Ns_UnlockMutex(&freelistMutex);
#else
#define FREELIST_MUTEX_LOCK
#define FREELIST_MUTEX_UNLOCK
#endif

/*----------------------------------------------------*
 * Hash table to collect region page reuse statistics *
 *  region_page_addr -> int                           *
 *----------------------------------------------------*/

#if ( REGION_PAGE_STAT )

RegionPageMap* 
regionPageMapInsert(RegionPageMap* regionPageMap, unsigned int addr)
{
  int index;
  RegionPageMapHashList* newElem;

  newElem = (RegionPageMapHashList*)malloc(sizeof(RegionPageMapHashList));
  if ( newElem <= (RegionPageMapHashList*)0 ) {
    die("regionPageMapInsert error");
  }

  newElem->n = 1;
  newElem->addr = addr;

  index = hashRegionPageIndex(addr);
  newElem->next = regionPageMap[index];

  regionPageMap[index] = newElem;
  return regionPageMap;    /* We want to allow for hash-table 
			    * resizing in the future */
}  

/* Create and allocate space for a new regionPageMapHashTable */
void 
regionPageMapZero(RegionPageMap* regionPageMap)
{
  int i;
  for ( i = 0 ; i < REGION_PAGE_MAP_HASH_TABLE_SIZE ; i++ ) 
    {
      regionPageMap[i] = NULL;
    }
}

RegionPageMap* 
regionPageMapNew(void) 
{
  RegionPageMap* regionPageMap;

  regionPageMap = (RegionPageMap*)malloc(sizeof(unsigned long) * REGION_PAGE_MAP_HASH_TABLE_SIZE);
  if ( regionPageMap <= 0 ) {
    die("Unable to allocate memory for RegionPageMapHashTable");
  }

  regionPageMapZero(regionPageMap);
  return regionPageMap;
}

RegionPageMap*
regionPageMapIncr(RegionPageMap* regionPageMap, unsigned int addr)
{
  RegionPageMapHashList* p;
  for ( p = regionPageMap[hashRegionPageIndex(addr)]; p != NULL ; p = p->next ) 
    {
      if ( p->addr == addr ) 
	{
	  p->n++;
	  return regionPageMap;
	}
    }
  return regionPageMapInsert(regionPageMap,addr);
}  

unsigned int
regionPageMapLookup(RegionPageMap* regionPageMap, unsigned int addr)
{
  RegionPageMapHashList* p;
  for ( p = regionPageMap[hashRegionPageIndex(addr)]; p != NULL ; p = p->next ) 
    {
      if ( p->addr == addr ) 
	{
	  return p->n;
	}
    }
  return (unsigned int) NULL;
}

void
regionPageMapClear(RegionPageMap* regionPageMap)
{
  int i;
  RegionPageMapHashList *p, *n;

  for ( i = 0 ; i < REGION_PAGE_MAP_HASH_TABLE_SIZE ; i++ ) 
    {
      p = regionPageMap[i];
      while ( p )
	{
	  n = p->next;
	  free(p);
	  p = n;
	}
      regionPageMap[i] = 0;
    }
}

RegionPageMap* rpMap = NULL;
#define REGION_PAGE_MAP_INCR(rp) (regionPageMapIncr(rpMap,(unsigned int)(rp)));
#else
#define REGION_PAGE_MAP_INCR(rp) 
#endif /* REGION_PAGE_STAT */

#if defined(SIMPLE_MEMPROF) && defined(ENABLE_GC)
int stack_min = 0; // updated by mutator - stack grows downwards
int lobjs_max_used = 0;
int rp_max_used = 0;
int rp_really_used = 0;

inline static void rp_max_check()
{
  if ( rp_really_used > rp_max_used )
    rp_max_used = rp_really_used;
  return;
}

inline static void lobjs_max_check()
{
  if ( lobjs_current > lobjs_max_used )
    lobjs_max_used = (int)lobjs_current;
  return;
}
#endif

/*----------------------------------------------------------------*
 * Global declarations                                            *
 *----------------------------------------------------------------*/
Klump * freelist = NULL;

#ifndef KAM
Ro * topRegion;
#endif

#ifdef ENABLE_GC
int rp_to_space = 0;
int rp_used = 0;
#endif /* ENABLE_GC */
int rp_total = 0;

#ifdef PROFILING
FiniteRegionDesc * topFiniteRegion = NULL;

unsigned int callsOfDeallocateRegionInf=0,
             callsOfDeallocateRegionFin=0,
             callsOfAlloc=0,
             callsOfResetRegion=0,
             callsOfDeallocateRegionsUntil=0,
             callsOfAllocateRegionInf=0,
             callsOfAllocateRegionFin=0,
             callsOfSbrk=0,
             maxNoOfPages=0,
             noOfPages=0,
             allocNowInf=0,             /* Allocated in inf. regions now. */
             maxAllocInf=0,             /* Max. allocatated data in inf. regions. */
             allocNowFin=0,             /* Allocated in fin. regions now. */
             maxAllocFin=0,             /* Max. allocated in fin. regions. */
             allocProfNowInf=0,         /* Words used on object descriptors in inf. regions. */
             maxAllocProfInf=0,         /* At time maxAllocInf how much were 
                                           used on object descriptors. */
             allocProfNowFin=0,         /* Words used on object descriptors in fin. regions. */
             maxAllocProfFin=0,         /* At time maxAllocFin how much were used on object descriptors. */
             maxAlloc=0,                /* Max. allocated data in both inf. and fin. regions. */
                                        /* Are not nessesarily equal to maxAllocInf+maxAllocFin!!! */

             regionDescUseInf=0,        /* Words used on non profiling information in inf. region descriptors. */
	     maxRegionDescUseInf=0,     /* Max. words used on non profiling information in inf. region descriptors. */
             regionDescUseProfInf=0,    /* Words used on profiling information in inf. region descriptors. */
	     maxRegionDescUseProfInf=0, /* Max. words used on profiling information in inf. region descriptors. */

             regionDescUseProfFin=0,    /* Words used on profiling information in fin. region descriptors. */
	     maxRegionDescUseProfFin=0, /* At time maxAllocFin, how much were used on finite region descriptors. */

             maxProfStack=0,            /* At time of max. stack size, how much is due to profiling.        */
                                        /* It is updated in function Profiling.updateMaxProfStack, which is */
                                        /* called from the assembler file.                                  */
             allocatedLobjs=0;          /* Total number of allocated large objects allocated with malloc */
#endif /*PROFILING*/

inline static unsigned int 
max(unsigned int a, unsigned int b) 
{
  return (a<b)?b:a;
}

/*------------------------------------------------------*
 * If an error occurs, then print the error and stop.   *
 *------------------------------------------------------*/
char errorStr[255];
void printERROR(char *errorStr) {
  printf("\n***********************ERROR*****************************\n");
  printf("%s\n", errorStr);
  printf("\n***********************ERROR*****************************\n");
  exit(-1);
}

/* Print info about a region. */
/*
void printTopRegInfo() {
  Ro *r;
  Klump *kp;

  r = (Ro *) clearStatusBits((int) TOP_REGION);
  printf("printRegInfo\n");
  printf("Region at address: %0x\n", r);
  printf("  fp: %0x\n", (r->fp));
  printf("  b : %0x\n", (r->b));
  printf("  a : %0x\n", (r->a));
  printf("  p : %0x\n", (r->p));

  printf("Region Pages\n");
  for (kp=r->fp;kp!=NULL;kp=kp->n)
    printf(" %0x\n ", kp);

  return;
}
*/

/* Print info about a region. */
/*
void printRegionInfo(int rAddr,  char *str) {
  Ro *r;
  Klump *kp;

  r = (Ro *) clearStatusBits(rAddr);
  printf("printRegionInfo called from: %s\n",str);
  printf("Region at address: %0x\n", r);
  printf("  fp: %0x\n", (r->fp));
  printf("  b : %0x\n", (r->b));
  printf("  a : %0x\n", (r->a));
  printf("  p : %0x\n", (r->p));

  printf("Region Pages\n");
  for (kp=r->fp;kp!=NULL;kp=kp->n)
    printf(" %0x\n ", kp);

  return;
}

void printRegionStack() {
  Ro *r;

  for(r=TOP_REGION;r!=NULL;r=r->p)
    printRegionInfo((int)r,"printRegionStack");

  return;
}
*/

/* Calculate number of pages in an infinite region. */
int NoOfPagesInRegion(Ro *r) {
  int i;
  Klump *rp;
  for ( i = 0, rp = clear_rtype(r->fp) ; rp ; rp = clear_tospace_bit(rp->n) ) 
    i++;
  return i;
}

/*
void printFreeList() {
  Klump *kp;

  printf("Enter printFreeList\n");
  FREELIST_MUTEX_LOCK;
  kp = freelist;
  while (kp != NULL) {
    printf(" %0x ",kp);
    kp = kp->n;
  }
  FREELIST_MUTEX_UNLOCK;
  printf("Exit printFreeList\n");
  return;
}
*/

#ifdef ENABLE_GC
int 
size_free_list() 
{
  Klump *rp;
  int i=0;

  FREELIST_MUTEX_LOCK;

  for ( rp = freelist ; rp ; rp = rp-> n )
    i++;

  FREELIST_MUTEX_UNLOCK;

  return i;
}
#endif /*ENABLE_GC*/

/*-------------------------------------------------------------------------*
 *                         Region operations.                              *
 *                                                                         *
 * allocateRegion: Allocates a region and return a pointer to it.          *
 * deallocateRegion: Pops the top region of the region stack.              *
 * callSbrk: Updates the freelist with new region pages.                   *
 * alloc: Allocates n words in a region.                                   *
 * resetRegion: Resets a region by freeing all pages except one            *
 * deallocateRegionsUntil: All regions above a threshold are deallocated.  *
 * deallocateRegionsUntil_X86: ---- for stack growing towards -inf         * 
 *-------------------------------------------------------------------------*/

/*----------------------------------------------------------------------*
 *allocateRegion:                                                       *
 *  Get a first regionpage for the region.                              *
 *  Put a region administrationsstructure on the stack. The address is  *
 *  in roAddr.                                                          *
 *----------------------------------------------------------------------*/
Region allocateRegion(Region r
#ifdef KAM
		    , Region* topRegionCell
#endif
		    ) { 
  Klump *rp;
  
  debug(printf("[allocateRegion..."));  

  r = clearStatusBits(r);

  FREELIST_MUTEX_LOCK;

  if ( freelist == NULL ) callSbrk();

  #ifdef ENABLE_GC
  rp_used++;
  #ifdef SIMPLE_MEMPROF
  rp_really_used++;
  rp_max_check();
  #endif
  #endif /* ENABLE_GC */

  rp = freelist;
  freelist = freelist->n;

  FREELIST_MUTEX_UNLOCK;

  REGION_PAGE_MAP_INCR(rp)   /* Niels - update frequency hashtable */

  rp->n = NULL;                  // First and last region page
  rp->r = r;                     // Point back To region descriptor

  r->a = (int *)(&(rp->i));      // We allocate from i in the page
  r->b = (int *)(rp+1);          // The border is after this page
  r->p = TOP_REGION;	         // Push this region onto the region stack
  r->fp = rp;                    // Update pointer to the first page
  r->lobjs = NULL;               // The list of large objects is empty
  
  TOP_REGION = r;

  r = (Ro *)setInfiniteBit((int)r);

  debug(printf("]\n"));

  return r;
}  

#ifdef ENABLE_GC
Region allocatePairRegion(Region r)
{
  r = allocateRegion(r);
  set_pairregion(clearStatusBits(r));
  return r;
}
#endif /*ENABLE_GC*/


void free_lobjs(Lobjs* lobjs)
{
  while ( lobjs ) 
    {
      Lobjs* lobjsTmp;
#ifdef ENABLE_GC
      unsigned int tag;
  #ifdef PROFILING
      tag = *((&(lobjs->value)) + sizeObjectDesc);
  #else
      tag = lobjs->value;
  #endif	  
      lobjs_current -= size_lobj(tag);
#endif	  
      lobjsTmp = clear_lobj_bit(lobjs->next);
#ifdef ENABLE_GC
      free(lobjs->orig);
#else
      free(lobjs);
#endif
      lobjs = lobjsTmp;
    }
}

/*----------------------------------------------------------------------*
 *deallocateRegion:                                                     *
 *  Pops the top region of the stack, and insert the regionpages in the *
 *  free list. There have to be atleast one region on the stack.        *
 *  When profiling we also use this function.                           *
 *----------------------------------------------------------------------*/
void deallocateRegion(
#ifdef KAM
		      Region* topRegionCell
#endif
		     ) { 
  int i;

  debug(printf("[deallocateRegion... top region: %x\n", TOP_REGION));

#ifdef PROFILING
  callsOfDeallocateRegionInf++;
  regionDescUseInf -= (sizeRo-sizeRoProf);
  regionDescUseProfInf -= sizeRoProf;
  i = NoOfPagesInRegion(TOP_REGION);
  noOfPages -= i;
  allocNowInf -= TOP_REGION->allocNow;
  allocProfNowInf -= TOP_REGION->allocProfNow;
  profTabDecrNoOfPages(TOP_REGION->regionId, i);
  profTabDecrAllocNow(TOP_REGION->regionId, TOP_REGION->allocNow, "deallocateRegion");
#endif

  #ifdef ENABLE_GC
  rp_used--;
  #ifdef SIMPLE_MEMPROF
  rp_really_used -= NoOfPagesInRegion(TOP_REGION);
  #endif
  #endif /* ENABLE_GC */

  free_lobjs(TOP_REGION->lobjs);

  /*
  if ( TOP_REGION->lobjs )
    {
      Lobjs* lobjs = TOP_REGION->lobjs;
      while ( lobjs ) 
	{
	  Lobjs* lobjsTmp;
#ifdef ENABLE_GC
	  unsigned int tag;
	  #ifdef PROFILING
	  tag = *((&(lobjs->value)) + sizeObjectDesc);
	  #else
	  tag = lobjs->value;
	  #endif	  
	  lobjs_current -= size_lobj(tag);
#endif	  
	  lobjsTmp = clear_lobj_bit(lobjs->next);
#ifdef ENABLE_GC
	  free(lobjs->orig);
#else
	  free(lobjs);
#endif
	  lobjs = lobjsTmp;
	}
    }
  */

  /* Insert the region pages in the freelist; there is always 
   * at-least one page in a region. */

  FREELIST_MUTEX_LOCK;
  (((Klump *)TOP_REGION->b)-1)->n = freelist;
  freelist = clear_rtype(TOP_REGION->fp);
  FREELIST_MUTEX_UNLOCK;

  TOP_REGION=TOP_REGION->p;

  debug(printf("]\n"));

  return;
}

inline static Lobjs *
alloc_lobjs(int n) {
#ifdef ENABLE_GC
  Lobjs* lobjs;
  char *p;
  int r;  
  p = (char*)malloc(4*(n+2) + 1024);
  if ( p == NULL )
    die("alloc_lobjs: malloc returned NULL");
  if ( r = (int)p % 1024 ) {
    lobjs = (Lobjs*)(p + 1024 - r);
  } else {
    lobjs = (Lobjs*)p;
  }
  lobjs->orig = p;
  return lobjs;
#else
  return (Lobjs*)malloc(4*(n+1));
#endif /* ENABLE_GC */
}

/*----------------------------------------------------------------------*
 *callSbrk:                                                             *
 *  Sbrk is called and the free list is updated.                        *
 *  The free list has to be empty.                                      *
 *----------------------------------------------------------------------*/
void callSbrk() { 
  Klump *np, *old_free_list;
  char *sb;
  int temp;

#ifdef PROFILING
  callsOfSbrk++;
#endif

  /* We must manually insure double alignment. Some operating systems (like *
   * HP UX) does not return a double aligned address...                     */

  /* For GC we require 1Kb alignments, that is the size of a region page! */

  sb = (char *)malloc(BYTES_ALLOC_BY_SBRK + 1024 /*8*/);

  if ( sb == NULL ) {
    perror("I could not allocate more memory; either no more memory is\navailable or the memory subsystem is detectively corrupted\n");
    exit(-1);
  }

  /* alignment (martin) */
  if ( temp = (int)sb % 1024 ) {
    sb = (char *) (((int)sb) + 1024 - temp);
  }

  if ( ! is_rp_aligned((unsigned int)sb) )
    die("SBRK region page is not properly aligned.");

  old_free_list = freelist;
  np = (Klump *) sb;
  freelist = np;

  rp_total++;

  /* fragment the SBRK-chunk into region pages */
  while ((char *)(np+1) < ((char *)freelist)+BYTES_ALLOC_BY_SBRK) { 
    np++;
    (np-1)->n = np;
    rp_total++;
  }
  np->n = old_free_list;

  #ifdef ENABLE_GC
  if (!disable_gc)
    time_to_gc = 1;
  #endif /* ENABLE_GC */

  return;
}

#ifdef ENABLE_GC_OLD
void callSbrkArg(int no_of_region_pages) { 
  Klump *np, *old_free_list;
  char *sb;
  int temp;
  int bytes_to_alloc;

#ifdef PROFILING
  callsOfSbrk++;
#endif

  /* We must manually insure double alignment. Some operating systems (like *
   * HP UX) does not return a double aligned address...                     */

  /* For GC we require 1Kb alignments, that is the size of a region page! */
  if (no_of_region_pages < REGION_PAGE_BAG_SIZE)
    no_of_region_pages = REGION_PAGE_BAG_SIZE;
  bytes_to_alloc = no_of_region_pages*sizeof(Klump);

  sb = (char *)malloc(bytes_to_alloc + 1024 /*8*/);

  if (sb == (char *)NULL) {
    perror("I could not allocate more memory; either no more memory is\navailable or the memory subsystem is detectively corrupted\n");
    exit(-1);
  }

  /* alignment (martin) */
  if (temp=((int)sb % 1024 /*8*/)) {
    sb = (char *) (((int)sb) + 1024 /*8*/ - temp);
  }

  if (!is_rp_aligned((unsigned int)sb))
    die("SBRK region page is not properly aligned.");

  /* The free list is not necessarily empty */
  old_free_list = freelist;
  np = (Klump *) sb;
  freelist = np;

  rp_total++;

  /* We have to fragment the SBRK-chunk into region pages. */
  while ((char *)(np+1) < ((char *)freelist)+bytes_to_alloc) { 
    np++;
    (np-1)->n = np;
    rp_total++;
  }
  np->n = old_free_list;

  if (!disable_gc)
    time_to_gc = 1;

  return;
}
#endif /* ENABLE_GC_OLD */

/*----------------------------------------------------------------------*
 *alloc_new_block:                                                      *
 *  Allocates a new block in region.                                    *
 *----------------------------------------------------------------------*/

void alloc_new_block(Ro *r) { 
  Klump* np;

#ifdef PROFILING
  profTabIncrNoOfPages(r->regionId, 1);
  profTabMaybeIncrMaxNoOfPages(r->regionId);
  maxNoOfPages = max(++noOfPages, maxNoOfPages);
#endif

  #ifdef ENABLE_GC
  #ifdef SIMPLE_MEMPROF
  rp_really_used++;
  rp_max_check();
  #endif
  rp_to_space++;
  rp_used++;
  if ( (!disable_gc) && (!time_to_gc) ) 
    {
      // the treshold suggests when we can garbage collect without allocating 
      // more memory.
      //      double treshold = (double)rp_total - (((double)rp_total) / heap_to_live_ratio);
      if ( rp_used > rp_gc_treshold )
	{
	  // calculate correct value for rp_used; the current value may exceed the correct
	  // value due to conservative computation in resetRegion, deallocRegion...
	  rp_used = rp_total - size_free_list();
	  if ( rp_used > rp_gc_treshold )
	    {
	      time_to_gc = 1;
	    }
	}
    }
  #endif /* ENABLE_GC */

  FREELIST_MUTEX_LOCK;
  if ( freelist == NULL ) callSbrk(); 
  np = freelist;
  freelist = freelist->n;

  REGION_PAGE_MAP_INCR(np); // update frequency hashtable

  FREELIST_MUTEX_UNLOCK;

#ifdef ENABLE_GC
  if ( doing_gc )
    np->n = set_tospace_bit(NULL);     // to-space bit
  else 
#endif
    np->n = NULL;
  np->r = r;         // Install origin-pointer - used by GC

  if ( clear_rtype(r->fp) )
#ifdef ENABLE_GC
    if ( doing_gc )
      (((Klump *)(r->b))-1)->n = set_tospace_bit(np); /* Updates the next field in the last region page. */
    else
#endif
      (((Klump *)(r->b))-1)->n = np; /* Updates the next field in the last region page. */
  else {
#ifdef ENABLE_GC
    int rt;
    if ( rt = rtype(r) )
      {
	r->fp = np;              /* Update pointer to the first page. */
	set_rtype(r,rt);
      }
    else 
#endif
      r->fp = np;                /* Update pointer to the first page. */
  }
  r->a = (int *)(&(np->i));      /* Updates the allocation pointer. */
  r->b = (int *)(np+1);          /* Updates the border pointer. */
}

/*----------------------------------------------------------------------*
 *alloc:                                                                *
 *  Allocates n words in region rAddr. It will make sure, that there    *
 *  is space for the n words before doing the allocation.               *
 *  Objects whose size n <= ALLOCATABLE_WORDS_IN_REGION_PAGE are        *
 *  allocated in region pages; larger objects are allocated using       *
 *  malloc.
 *----------------------------------------------------------------------*/
int *alloc (Region r, int n) { 
  int *t1;
  int *t2;
  int *t3;

#if defined(PROFILING) || defined(ENABLE_GC)
  int *i;
#endif

  /*  debug(printf("[alloc, r=%x, n=%d, topFiniteRegion = %x, ...\n", r, 9, topFiniteRegion)); */
  r = clearStatusBits(r);

#ifdef ENABLE_GC
  //  if ( is_pairregion(r) )
  //    printf("alloc: allocating %d words in pair region\n", n);
#endif

  /*  debug(printf("[alloc, r=%x, id=%d, n=%d, topFiniteRegion = %x ...\n", r, r->regionId, n, topFiniteRegion)); */

  /*  printRegionStack();*/
  /*  printRegionInfo((int)r,"from alloc ");*/

#ifdef PROFILING
  allocNowInf += n-sizeObjectDesc; /* When profiling we also allocate an object descriptor. */
  maxAlloc = max(maxAlloc, allocNowInf+allocNowFin);
  r->allocNow += n-sizeObjectDesc;
  /*  checkProfTab("profTabIncrAllocNow.entering.alloc");  */
  profTabIncrAllocNow(r->regionId, n-sizeObjectDesc);

  callsOfAlloc++;
  maxAllocInf = max(allocNowInf, maxAllocInf);
  allocProfNowInf += sizeObjectDesc;
  if (maxAllocInf == allocNowInf) maxAllocProfInf = allocProfNowInf;
  r->allocProfNow += sizeObjectDesc;
#endif

  // see if the size of requested memory exceeds 
  // the size of a region page */

  if ( n > ALLOCATABLE_WORDS_IN_REGION_PAGE )   // notice: n is in words
    {
      Lobjs* lobjs;
      lobjs = alloc_lobjs(n);
      lobjs->next = set_lobj_bit(r->lobjs);
      r->lobjs = lobjs;
      #ifdef PROFILING
      //    fprintf(stderr,"Allocating Large Object %d bytes\n", 4*n);
      allocatedLobjs++;
      #endif
#ifdef ENABLE_GC
      lobjs_current += 4*n;
      lobjs_period += 4*n;
      if ( (!disable_gc) && (lobjs_current>lobjs_gc_treshold) ) 
	{
	  time_to_gc = 1;
	}
#endif
#if defined(SIMPLE_MEMPROF) && defined(ENABLE_GC)
      lobjs_max_check();
#endif
      return &(lobjs->value);
    }

#ifdef ENABLE_GC
  alloc_period += 4*n;
#endif

  t1 = r->a;
  t2 = t1 + n;

  t3 = r->b;
  if (t2 > t3) {
    #if defined(PROFILING) || defined(ENABLE_GC)
       /* insert zeros in the rest of the current region page */
       for ( i = t1 ; i < t3 ; i++ )  *i = notPP;
    #endif 
    alloc_new_block(r);

    t1 = r->a;
    t2 = t1+n;
  }
  r->a = t2;

  debug(printf("]\n"));

  return t1;
}

/*----------------------------------------------------------------------*
 *resetRegion:                                                          *
 *  All regionpages except one are inserted into the free list, and     *
 *  the region administration structure is updated. The statusbits are  *
 *  not changed.                                                        *
 *----------------------------------------------------------------------*/
Region 
resetRegion(Region rAdr) 
{ 
  Ro *r;
  
#ifdef PROFILING
  int *i;
  Klump *temp;
  int j;
#endif

  debug(printf("[resetRegions..."));

  r = clearStatusBits(rAdr);

#ifdef PROFILING
  callsOfResetRegion++;
  j = NoOfPagesInRegion(r);

  /* There is always at-least one page in a region. */
  noOfPages -= j-1;
  profTabDecrNoOfPages(r->regionId, j-1);

  allocNowInf -= r->allocNow;
  profTabDecrAllocNow(r->regionId, r->allocNow, "resetRegion");
  allocProfNowInf -= r->allocProfNow;
#endif

  /* There is always at least one page in a region. */
  if ( (clear_rtype(r->fp))->n ) { /* There are more than one page in the region. */

    #ifdef ENABLE_GC
    rp_used--;              // at least one page is freed; see comment in alloc_new_block
                            //   concerning conservative computation.
    #ifdef SIMPLE_MEMPROF
    rp_really_used -= NoOfPagesInRegion(r) - 1;
    #endif
    #endif /* ENABLE_GC */  

    FREELIST_MUTEX_LOCK;
    (((Klump *)r->b)-1)->n = freelist;
    freelist = (clear_rtype(r->fp))->n;
    FREELIST_MUTEX_UNLOCK;
    (clear_rtype(r->fp))->n = NULL;
  }

  r->a = (int *)(&(clear_rtype(r->fp))->i);   /* beginning of klump in first page */
  r->b = (int *)((clear_rtype(r->fp))+1);     /* end of klump in first page */

  free_lobjs(r->lobjs);
  r->lobjs = NULL;

#ifdef PROFILING
  r->allocNow = 0;
  r->allocProfNow = 0;
#endif

  debug(printf("]\n"));

  return rAdr; /* We preserve rAdr and the status bits. */
}

/*-------------------------------------------------------------------------*
 *deallocateRegionsUntil:                                                  *
 *  It is called with rAddr=sp, which do not nessesaraly point at a region *
 *  description. It deallocates all regions that are placed over sp.       *
 *  The function does not return or alter anything.                        *
 *-------------------------------------------------------------------------*/
void 
deallocateRegionsUntil(Region r
#ifdef KAM
		       , Region* topRegionCell
#endif
		       ) 
{ 
  // debug(printf("[deallocateRegionsUntil(r = %x, topFiniteRegion = %x)...\n", r, topFiniteRegion));

  r = clearStatusBits(r);
  
#ifdef PROFILING
  callsOfDeallocateRegionsUntil++;
  while ((FiniteRegionDesc *)r <= topFiniteRegion)
    {
      deallocRegionFiniteProfiling();
    }
#endif

  while (r <= TOP_REGION) 
    { 
      /*printf("r: %0x, top region %0x\n",r,TOP_REGION);*/
      deallocateRegion(
#ifdef KAM
		       topRegionCell
#endif
		      );
    }

  debug(printf("]\n"));

  return;
} 

/*-------------------------------------------------------------------------*
 *deallocateRegionsUntil_X86: version of the above function working with   *
 *  the stack growing towards negative infinity.                           *
 *-------------------------------------------------------------------------*/
#ifndef KAM
void 
deallocateRegionsUntil_X86(Region r) 
{ 
  //  debug(printf("[deallocateRegionsUntil_X86(r = %x, topFiniteRegion = %x)...\n", r, topFiniteRegion));

  r = clearStatusBits(r);
  
#ifdef PROFILING
  callsOfDeallocateRegionsUntil++;

  /* Don't call deallocRegionFiniteProfiling if no finite 
   * regions are allocated. mael 2001-03-20 */
  while ( topFiniteRegion && (FiniteRegionDesc *)r >= topFiniteRegion)
    {
      deallocRegionFiniteProfiling();
    }
#endif

  while (r >= TOP_REGION) 
    {
      /*printf("r: %0x, top region %0x\n",r,TOP_REGION);*/
      deallocateRegion();
    }

  debug(printf("]\n"));

  return;
} 
#endif /* not KAM */



/*----------------------------------------------------------------*
 *        Profiling functions                                     *
 *----------------------------------------------------------------*/
#ifdef PROFILING

/***************************************************************************
 *     Changed runtime operations for making profiling possible.           *
 *                                                                         *
 *                                                                         *
 * allocRegionInfiniteProfiling(roAddr, regionId)                          *
 * allocRegionFiniteProfiling(rdAddr, regionId, size)                      *
 * deallocRegionFiniteProfiling(void)                                      *
 * allocProfiling(rAddr, n, pPoint)                                        *
 ***************************************************************************/

/*----------------------------------------------------------------------*
 *allocRegionInfiniteProfiling:                                         *
 *  Get a first regionpage for the region.                              *
 *  Put a region administration structure on the stack. The address is  *
 *  in roAddr. The name of the region is regionId                       *
 *  There has to be room for the region descriptor on the stack, which  *
 *  roAddr points at.                                                   *
 *----------------------------------------------------------------------*/
Region
allocRegionInfiniteProfiling(Region r, unsigned int regionId) { 
  Klump *rp;

  /* printf("[allocRegionInfiniteProfiling r=%x, regionId=%d...", r, regionId);*/

  callsOfAllocateRegionInf++;
  maxNoOfPages = max(++noOfPages, maxNoOfPages);
  profTabIncrNoOfPages(regionId, 1);
  profTabMaybeIncrMaxNoOfPages(regionId);
  regionDescUseInf += (sizeRo-sizeRoProf);
  maxRegionDescUseInf = max(maxRegionDescUseInf,regionDescUseInf);
  regionDescUseProfInf += sizeRoProf;
  maxRegionDescUseProfInf = max(maxRegionDescUseProfInf,regionDescUseProfInf);

  FREELIST_MUTEX_LOCK;

  if ( freelist == NULL ) callSbrk();

  #ifdef ENABLE_GC
  rp_used++;
  #ifdef SIMPLE_MEMPROF
  rp_really_used++;
  rp_max_check();
  #endif
  #endif /* ENABLE_GC */

  rp = freelist;
  freelist = freelist->n;

  FREELIST_MUTEX_UNLOCK;

  rp->n = NULL;                  // First and last region page
  rp->r = r;                     // Pointer back to region descriptor (used by GC)

  r->a = (int *)(&(rp->i));      // We allocate from i in the page
  r->b = (int *)(rp+1);          // The border is after this page
  r->p = TOP_REGION;	         // Push this region onto the region stack
  r->fp = rp;                    // Update pointer to the first page
  r->allocNow = 0;               // No allocation yet
  r->allocProfNow = 0;           // No allocation yet
  r->regionId = regionId;        // Put name of region in region descriptor

  r->lobjs = NULL;               // The list of large objects is empty

  TOP_REGION = r;

  r = (Region)setInfiniteBit((int)r);

  debug(printf("exiting]\n"));

  return r;
}

/* In CodeGenX86, we use a generic function to compile a C-call. The regionId */
/* may therefore be tagged, which this stub-function takes care of.           */
Region
allocRegionInfiniteProfilingMaybeUnTag(Region r, unsigned int regionId) 
{ 
  return allocRegionInfiniteProfiling(r, convertIntToC(regionId));
}

#ifdef ENABLE_GC
Region
allocPairRegionInfiniteProfiling(Region r, unsigned int regionId) 
{
  r = allocRegionInfiniteProfiling(r, regionId);
  set_pairregion(clearStatusBits(r));
  return r;
}

Region
allocPairRegionInfiniteProfilingMaybeUnTag(Region r, unsigned int regionId) 
{ 
  r = allocRegionInfiniteProfiling(r, convertIntToC(regionId));
  set_pairregion(clearStatusBits(r));
  return r;
}
#endif /*ENABLE_GC*/ 

/*-------------------------------------------------------------------------------*
 * allocRegionFiniteProfiling:                                                   *
 * Program point 0 is used as indication no object at all in the runtime system. *
 * Program point 1 is used when a finite region is allocated but the correct     *
 * program point is not known.                                                   *
 * The first correct program point is 2.                                         *
 * There has to be room on the stack for the finite region descriptor and the    *
 * object descriptor. rdAddr points at the region descriptor when called.        *
 *-------------------------------------------------------------------------------*/
#define notPrgPoint 1 
void allocRegionFiniteProfiling(FiniteRegionDesc *rdAddr, unsigned int regionId, int size) { 
  ObjectDesc *objPtr;  
  ProfTabList* p;
  int index;
/*
  printf("[Entering allocRegionFiniteProfiling, rdAddr=%x, regionId=%d, size=%d ...\n", rdAddr, regionId, size);
*/
  allocNowFin += size;                                  /* necessary for graph drawing */
  maxAlloc = max(maxAlloc, allocNowFin+allocNowInf);    /* necessary for graph drawing */

  callsOfAllocateRegionFin++;
  maxAllocFin = max(allocNowFin, maxAllocFin);
  allocProfNowFin += sizeObjectDesc;
  regionDescUseProfFin += sizeFiniteRegionDesc;
  if (allocNowFin == maxAllocFin) {
    maxAllocProfFin = allocProfNowFin;
    maxRegionDescUseProfFin = regionDescUseProfFin;
  }
  /*  checkProfTab("profTabIncrAllocNow.entering.allocRegionFiniteProfiling"); */
  profTabIncrAllocNow(regionId, size);

  rdAddr->p = topFiniteRegion;   /* link to previous region description on stack */
  rdAddr->regionId = regionId;   /* put name on region in descriptor. */
  topFiniteRegion = rdAddr;      /* pointer to topmost region description on stack */

  objPtr = (ObjectDesc *)(rdAddr + 1); /* We also put the object descriptor onto the stack. */
  objPtr->atId = notPrgPoint;
  objPtr->size = size;

  debug(printf("exiting, topFiniteRegion = %x, topFiniteRegion->p = %x, &topFiniteRegion = %x]\n", 
  	       topFiniteRegion, topFiniteRegion->p, &topFiniteRegion));

  return;
}

/* In CodeGenX86, we use a generic function to compile a C-call. The regionId */
/* and size may therefore be tagged, which this stub-function takes care of.  */
void allocRegionFiniteProfilingMaybeUnTag(FiniteRegionDesc *rdAddr, unsigned int regionId, int size) { 
  return allocRegionFiniteProfiling(rdAddr, convertIntToC(regionId), convertIntToC(size));
}

/*-----------------------------------------------------------------*
 * deallocRegionFiniteProfiling:                                   *
 * topFiniteRegion has to point at the bottom address of the       *
 * finite region descriptor, which will be the new stack address.  *
 *-----------------------------------------------------------------*/
int *deallocRegionFiniteProfiling(void) { 
  int size;

  /*
  printf("[Entering deallocRegionFiniteProfiling regionId=%d (topFiniteRegion = %x)...\n",
	 topFiniteRegion->regionId, topFiniteRegion);
  */
  size = ((ObjectDesc *) (topFiniteRegion + 1))->size;
  allocNowFin -= size;                                    /* necessary for graph drawing */

  callsOfDeallocateRegionFin++;
  profTabDecrAllocNow(topFiniteRegion->regionId, size, "deallocRegionFiniteProfiling");
  allocProfNowFin -= sizeObjectDesc;
  regionDescUseProfFin -= sizeFiniteRegionDesc;

  topFiniteRegion = topFiniteRegion->p;                   /* pop ptr. to prev. region desc. */

  debug(printf("exiting, topFiniteRegion = %x]\n", topFiniteRegion));
}


/*-----------------------------------------------------------------*
 * allocProfiling:                                                 *
 * Same as alloc, except that an object descriptor is created.     *
 * In particular, n is still the number of words requested for     *
 * user values (not including the object descriptor).  However,    *
 * allocProfiling asks alloc for space for the object descriptor   *
 * and takes care of allocating it, returning a pointer to the     *
 * beginning of the user value, as if profiling is not enabled.    *
 *-----------------------------------------------------------------*/
int *allocProfiling(Region r,int n, int pPoint) {
  int *res;

  debug(printf("[Entering allocProfiling... r:%x, n:%d, pp:%d.", r, n, pPoint));

  res = alloc(r, n+sizeObjectDesc);       // allocate object descriptor and object
  
  ((ObjectDesc *)res)->atId = pPoint;     // initialize object descriptor
  ((ObjectDesc *)res)->size = n;
  
  res = (int *)(((ObjectDesc *)res) + 1); // return pointer to user data

  debug(printf("exiting]\n"));
  return res;
}

#endif /*PROFILING*/

#ifdef KAM
void free_region_pages(Klump* first, Klump* last)
{
  if ( first == 0 )
    return;
  FREELIST_MUTEX_LOCK;
  last->n = freelist;
  freelist = first;
  FREELIST_MUTEX_UNLOCK;
  return;
}
#endif /*KAM*/
