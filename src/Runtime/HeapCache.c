#include "HeapCache.h"
#include "Region.h"
#include "Runtime.h"

/*
 * Checkpointing execution of library code
 */

/*
 * Static function declarations
 */

// [newHeap()] returns an uninitialized heap - with status 
// HSTAT_UNINITIALIZED.
static Heap* newHeap(void);

// [restoreHeap(h)] restores the heap from the heap copy information.
// Changes the heap status to HSTAT_CLEAN. Requires the heap status to
// be HSTAT_DIRTY. 
static void restoreHeap(Heap *h);

// [pagesInRegion(r)] returns the number of pages associated with r.
static int pagesInRegion(Ro *r);

// [copyRegion(r)] copies the content of the region r into a malloced
// data structure containing all pages from the region and region
// descriptor information.
static RegionCopy* copyRegion(Ro *r);

// [restoreRegion(rc)] restores the region rc->r from the region copy rc
// by copying back the original region page contents into the first
// region pages in the region. The function frees the remaining pages
// of the region. Returns 0 on success and -1 on error.
static int restoreRegion(RegionCopy *rc);


static int heapid_counter = 0;

#include "Locks.h"

static void
dienow(char *s)
{
#if defined(AOLSERVER)
  Ns_Log(Notice,"die2: %s",s);
#elif defined(APACHE)
  logMsg(s);
#endif
  die(s);
}

/*
static void 
dienow(char *s)
{
  die(s);
}
*/

static Heap* heapPool[MAX_HEAP_POOL_SZ];
static int heapPoolIndex = 0;

// Invariant: if heapPoolIndex == 0 then there are no heaps in the
// heapPool to choose from; otherwise, the heapPool contains a heap
// we can use (index heapPoolIndex). Each heap in the pool has status
// HSTAT_CLEAN.

// [pagesInRegion(r)] returns the number of pages associated with r.
static int pagesInRegion(Ro *r)
{
  Rp *p;
  int n = 0;
  for ( p = r->g0.fp ; p ; p = p->n )
    n++;
  return n;
}

static RegionCopy* copyRegion(Ro *r)
{
  int np, bytes, *q;
  Rp *p;
  RegionCopy *rc;

  if ( r->lobjs ) 
    {
      int c = 0;
      Lobjs* lobjs;
      for ( lobjs = r->lobjs ; lobjs ; lobjs = lobjs->next )
	c++;
      dienow ("copyRegion: copying of large objects not supported");
    }
  // printf("entering copyRegion r = %x\n", r);

  np = pagesInRegion(r);

  // printf("%d pages\n", np);

  bytes = sizeof(RegionCopy) + 4                             // for final null-pointer
    + np * (4 * (ALLOCATABLE_WORDS_IN_REGION_PAGE + 1));     // + 1 is for page pointer 
  rc = (RegionCopy*)malloc(bytes);
  
  rc->r = r;     // not really necessary
  rc->a = r->g0.a;
  rc->b = r->g0.b;

  q = rc->pages;
  for ( p = r->g0.fp ; p ; p = p->n )
    {
      int i = 0;
      *q++ = (int)p;                             // set pointer to original page
      while ( i < ALLOCATABLE_WORDS_IN_REGION_PAGE )
	*q++ = p->i[i++];
    }
  *q = 0;    // final null-pointer
  return rc;
}

static int restoreRegion(RegionCopy *rc)
{
  Rp *p = 0;
  Rp *p_next = 0;
  int i = 0;

  while ( p_next = (Rp*)(rc->pages[i++]) )   // pointer to original region page is stored in copy!
    {
      int j = 0;
      p = p_next;
      while ( j < ALLOCATABLE_WORDS_IN_REGION_PAGE )
	p->i[j++] = rc->pages[i++];
    }

  free_region_pages(p->n,((Rp*)rc->r->g0.b)-1);

  p->n = NULL;                // there is at least one page
  rc->r->g0.a = rc->a;
  rc->r->g0.b = rc->b;
  free_lobjs(rc->r->lobjs);
  rc->r->lobjs = NULL;
  return 0;
}

static Heap* newHeap(void)
{
  Heap* h;
  h = (Heap*)malloc(sizeof(Heap));
  if ( h == 0 )
    dienow ("newHeap: couldn't allocate room for heap");
  h->status = HSTAT_UNINITIALIZED;
  h->r0copy = NULL;
  h->r2copy = NULL;
  h->r3copy = NULL;
  h->r4copy = NULL;
  h->r5copy = NULL;
  h->r6copy = NULL;
  h->sp = NULL;
  return h;
}

Heap* getHeap(void)
{
  Heap* h;

  LOCK_LOCK(STACKPOOLMUTEX);
  if ( heapPoolIndex )
    {
      h = heapPool[--heapPoolIndex];
      LOCK_UNLOCK(STACKPOOLMUTEX);
    }
  else   // allocate new heap
    { 
      int hid = heapid_counter++;
      LOCK_UNLOCK(STACKPOOLMUTEX);
      h = newHeap();
      h->heapid = hid;
    }

  return h;
}

void touchHeap(Heap* h)
{
  if ( h->status != HSTAT_CLEAN )
    dienow("touchHeap: status <> HSTAT_CLEAN");
  h->status = HSTAT_DIRTY;
}

static void freePages(RegionCopy *rc)
{
  if ( rc ) 
    {
      free_region_pages(rc->r->g0.fp, (Rp*)(rc->r->g0.b) - 1);
      free(rc);
    }  
}

void deleteHeap(Heap *h)
{
  freePages(h->r0copy);
  freePages(h->r2copy);
  freePages(h->r3copy);
  freePages(h->r4copy);
  freePages(h->r5copy);
  freePages(h->r6copy);
  free(h);
}

void releaseHeap(Heap *h)
{
  restoreHeap(h);
  LOCK_LOCK(STACKPOOLMUTEX);
  if ( heapPoolIndex < MAX_HEAP_POOL_SZ ) 
    {
      heapPool[heapPoolIndex++] = h;
      LOCK_UNLOCK(STACKPOOLMUTEX);
    }
  else
    {
      LOCK_UNLOCK(STACKPOOLMUTEX);
      deleteHeap(h);
    } 
}

static void restoreHeap(Heap *h)
{
  int i;
  if ( h->status != HSTAT_DIRTY )
    dienow ("restoreHeap: status <> HSTAT_DIRTY");
 
  if ( restoreRegion(h->r0copy) == -1 )
    dienow ("restoreHeap: failed to restore r0");

  if ( restoreRegion(h->r2copy) == -1 )
    dienow ("restoreHeap: failed to restore r2");

  if ( restoreRegion(h->r3copy) == -1 )
    dienow ("restoreHeap: failed to restore r3");

  if ( restoreRegion(h->r4copy) == -1 )
    dienow ("restoreHeap: failed to restore r4");

  if ( restoreRegion(h->r5copy) == -1 )
    dienow ("restoreHeap: failed to restore r5");

  if ( restoreRegion(h->r6copy) == -1 )
    dienow ("restoreHeap: failed to restore r6");

  for ( i = 0 ; i < LOWSTACK_COPY_SZ ; i++ )
    {
      *(h->sp - i - 1) = h->lowStack[i];
    }

  h->status = HSTAT_CLEAN;
}

void initializeHeap(Heap *h, int *sp, int *exnPtr, unsigned long exnCnt)
{
  int i;
  Ro *r0, *r2, *r3, *r4, *r5, *r6; 

  if ( h->status != HSTAT_UNINITIALIZED )
    dienow ("initializeHeap: status <> HSTAT_UNINITIALIZED");

  r0 = clearStatusBits(*(Ro**)(h->ds));    // r0 is a pointer to a region description on the stack
  r2 = r0+1;                               // r2 is a pointer to the next region description on the stack
  r3 = r0+2;
  r4 = r0+3;
  r5 = r0+4;
  r6 = r0+5;
  
  h->sp = sp;
  h->exnPtr = exnPtr;
  h->exnCnt = exnCnt;

  //  printf("r0 = %x, r2 = %x, r3=%x, h=%x, ds=%x\n", r0,r2,r3,h,h->ds);

  h->r0copy = copyRegion(r0);
  h->r2copy = copyRegion(r2);
  h->r3copy = copyRegion(r3);
  h->r4copy = copyRegion(r4);
  h->r5copy = copyRegion(r5);
  h->r6copy = copyRegion(r6);

  for ( i = 0 ; i < LOWSTACK_COPY_SZ ; i++ )
    {
      h->lowStack[i] = *(sp - i - 1);
    }

  h->status = HSTAT_CLEAN;
}

void 
clearHeapCache()
{
  Heap *h;

  LOCK_LOCK(STACKPOOLMUTEX);
  while ( heapPoolIndex )
    {
      h = heapPool[--heapPoolIndex];
      deleteHeap(h);      
    }
  LOCK_UNLOCK(STACKPOOLMUTEX);
  return;
}
