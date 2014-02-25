//
//  ARCollectionViewController.m
//  Argos
//
//  Created by Francis Tseng on 2/24/14.
//  Copyright (c) 2014 Argos. All rights reserved.
//

#import "ARCollectionViewController.h"

@interface ARCollectionViewController () {
    NSString *_title;
    NSString *_entityName;
}
@end

@implementation ARCollectionViewController

- (id)initWithCollectionViewLayout:(UICollectionViewLayout*)collectionViewLayout forEntityNamed:(NSString*)entityName {
    self = [super initWithCollectionViewLayout:collectionViewLayout];
    if (self) {
        _entityName = entityName;
        _sortKey = @"createdAt"; // default sort key
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Hack to do back buttons w/o text.
	self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    self.navigationItem.hidesBackButton = YES;
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    self.collectionView = [[ARCollectionView alloc] initWithFrame:screenRect collectionViewLayout:self.collectionViewLayout];
}

# pragma mark - UICollectionViewDelegate
- (UICollectionViewCell*)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    ARCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CellIdentifier forIndexPath:indexPath];
    
    cell.contentView.backgroundColor = [UIColor whiteColor];
    
    //[cell setDefaultColor:[UIColor secondaryColor]];
    
    return cell;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return [[self.fetchedResultsController sections] count];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][section];
    return [sectionInfo numberOfObjects];
}

# pragma mark - NSFetchedResultsControllerDelegate
- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // Edit the entity name as appropriate.
    NSEntityDescription *entity = [NSEntityDescription entityForName:_entityName inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:20];
    
    // Edit the sort key as appropriate.
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:_sortKey ascending:NO];
    NSArray *sortDescriptors = @[sortDescriptor];
    
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.managedObjectContext sectionNameKeyPath:nil cacheName:@"Master"];
    aFetchedResultsController.delegate = self;
    self.fetchedResultsController = aFetchedResultsController;
    
	NSError *error = nil;
	if (![self.fetchedResultsController performFetch:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
	    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
	    abort();
	}
    
    return _fetchedResultsController;
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    // In the simplest, most efficient, case, reload the table view.
    [self.collectionView reloadData];
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate)
    {
        [self loadImagesForOnscreenRows];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self loadImagesForOnscreenRows];
}

# pragma mark - Image Loading
- (void)loadImagesForOnscreenRows
{
    NSArray *visiblePaths = [self.collectionView indexPathsForVisibleItems];
    for (NSIndexPath *indexPath in visiblePaths) {
        id<Entity> entity = [self.fetchedResultsController objectAtIndexPath:indexPath];
        if (!entity.image) {
            [self downloadImageForEntity:entity forIndexPath:indexPath];
        }
    }
    
    // If only one cell is visible on screen,
    // i.e. we have full screen cells,
    // then preload the next and previous two images.
    // Assumes one section.
    if (visiblePaths.count == 1) {
        NSIndexPath* indexPath = visiblePaths.firstObject;
        int start = (int)indexPath.row;
        
        for (int i=1; i<=2; i++) {
            int next = start + i;
            if (next < self.fetchedResultsController.fetchedObjects.count) {
                NSIndexPath* nextIndexPath = [NSIndexPath indexPathForRow:next inSection:0];
                id<Entity> entity = [self.fetchedResultsController objectAtIndexPath:nextIndexPath];
                if (!entity.image) {
                    [self downloadImageForEntity:entity forIndexPath:nextIndexPath];
                }
            }
        }
        
        for (int i=1; i<=2; i++) {
            int prev = start - i;
            if (prev >= 0) {
                NSIndexPath* prevIndexPath = [NSIndexPath indexPathForRow:prev inSection:0];
                id<Entity> entity = [self.fetchedResultsController objectAtIndexPath:prevIndexPath];
                if (!entity.image) {
                    [self downloadImageForEntity:entity forIndexPath:prevIndexPath];
                }
            }
        }
        
    }
}

- (void)downloadImageForEntity:(id<Entity>)entity forIndexPath:(NSIndexPath*)indexPath
{
    NSURL* imageUrl = [NSURL URLWithString:entity.imageUrl];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSError* error = nil;
        NSData *imageData = [NSData dataWithContentsOfURL:imageUrl options:NSDataReadingUncached error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            ARCollectionViewCell* cell = (ARCollectionViewCell*)[self.collectionView cellForItemAtIndexPath:indexPath];
            
            UIImage* image = [UIImage imageWithData:imageData];
            entity.image = image;
            
            // Crop the image
            // Need to double cell height for retina.
            // This isn't working, not sure why.
            CGSize dimensions = CGSizeMake(cell.imageSize.width*2, cell.imageSize.height*2);
            UIImage *croppedImage = [image scaleToCoverSize:dimensions];
            croppedImage = [croppedImage cropToSize:dimensions usingMode:NYXCropModeCenter];
            
            // Update the UI
            cell.imageView.image = croppedImage;
        });
    });
}

- (void)handleImageForEntity:(id<Entity>)entity forCell:(ARCollectionViewCell*)cell atIndexPath:(NSIndexPath*)indexPath
{
    // If there's no cached image for this event,
    // consider loading it.
    if (!entity.image) {
        // Only start loading images when scrolling stops.
        if (self.collectionView.dragging == NO && self.collectionView.decelerating == NO) {
            [self downloadImageForEntity:entity forIndexPath:indexPath];
            
            // Otherwise use the placeholder image.
        } else {
            cell.imageView.image = [UIImage imageNamed:@"placeholder"];
        }
        
        // If there is a cached image, use it.
    } else {
        CGSize dimensions = CGSizeMake(cell.imageSize.width*2, cell.imageSize.height*2);
        UIImage *croppedImage = [entity.image scaleToCoverSize:dimensions];
        croppedImage = [croppedImage cropToSize:dimensions usingMode:NYXCropModeCenter];
        cell.imageView.image = croppedImage;
    }
}


@end
