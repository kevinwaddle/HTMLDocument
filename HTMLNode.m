/*###################################################################################
 #																					#
 #    HTMLNode.m																	#
 #																					#
 #    Copyright © 2011 by Stefan Klieme                                             #
 #																					#
 #	  Objective-C wrapper for HTML parser of libxml2								#
 #																					#
 #	  Version 1.1 - 3. Apr 2012                                                     #
 #																					#
 #    usage:     add libxml2.dylib to frameworks                                    #
 #               add $SDKROOT/usr/include/libxml2 to target -> Header Search Paths  #
 #               add -lxml2 to target -> other linker flags                         #
 #                                                                                  #
 ####################################################################################
 #																					#
 # Permission is hereby granted, free of charge, to any person obtaining a copy of  #
 # this software and associated documentation files (the "Software"), to deal       #
 # in the Software without restriction, including without limitation the rights     #
 # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies #
 # of the Software, and to permit persons to whom the Software is furnished to do   #
 # so, subject to the following conditions:                                         #
 # The above copyright notice and this permission notice shall be included in       #
 # all copies or substantial portions of the Software.                              #
 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR       #
 # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,         #
 # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE      #
 # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,# 
 # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR     #
 # IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.	#
 #																					#
 ###################################################################################*/


// category of NSString for collapsing characters within a string

@interface NSString (SKHTMLNode)  

- (NSString *)collapseCharactersinSet:(NSCharacterSet *)characterSet usingSeparator:(NSString *)separator;
- (NSString *)collapseWhitespaceAndNewLine;

@end

@implementation NSString (SKHTMLNode)

// method to collapse all multiple occurrences of characters of a given character set 
// within the string into the given separator
- (NSString *)collapseCharactersinSet:(NSCharacterSet *)characterSet usingSeparator:(NSString *)separator
{
    if (characterSet == nil) return self;
    
    NSMutableArray *array;
    array = [[NSMutableArray alloc] initWithArray:[self componentsSeparatedByCharactersInSet:characterSet]];
    [array removeObject:@""]; // remove all occurrences of empty string items from the array
    NSString *result = [array componentsJoinedByString:separator];
    return result;
}

- (NSString *)collapseWhitespaceAndNewLine
{
    return [self collapseCharactersinSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] usingSeparator:@" "];
}

@end


/*****************************************************************************************************/

#import "HTMLNode.h"

#define DUMP_BUFFER_SIZE 1024
#define XML_CHECK_CONTENT(n) (n->children && n->children->content) ? YES : NO

// C functions for less overhead in recursion

void textContentOfChildren(xmlNode * node, NSMutableArray * array, BOOL recursive);
NSString * textContent(xmlNode *node);
void arrayOfTextContent(xmlNode * node, NSMutableArray * array, BOOL recursive);
HTMLNode * childWithAttributeValueMatches(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, BOOL recursive);
HTMLNode * childWithAttributeValueContains(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, BOOL recursive);
void childrenWithAttributeValueMatches(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, NSMutableArray * array, BOOL recursive);
void childrenWithAttributeValueContains(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, NSMutableArray * array, BOOL recursive);
HTMLNode * childOfTagValueMatches(const xmlChar * tagName, const xmlChar * value, xmlNode * node, BOOL recursive);
HTMLNode * childOfTagValueContains(const xmlChar * tagName, const xmlChar * value, xmlNode * node, BOOL recursive);
void childrenOfTagValueMatches(const xmlChar * tagName, const xmlChar * value, xmlNode * node, NSMutableArray * array, BOOL recursive);
void childrenOfTagValueContains(const xmlChar * tagName, const xmlChar * value, xmlNode * node, NSMutableArray * array, BOOL recursive);
HTMLNode * childOfTag(const xmlChar * tagName, xmlNode * node, BOOL recursive);
void childrenOfTag(const xmlChar * tagName, xmlNode * node, NSMutableArray * array, BOOL recursive);


@implementation HTMLNode
@synthesize xpathError;

#pragma mark - class method

// convenience initializer
+ (HTMLNode *)nodeWithXMLNode:(xmlNode *)xmlNode
{
	return [[HTMLNode alloc] initWithXMLNode:xmlNode];	
}

#pragma mark - init method


- (id)initWithXMLNode:(xmlNode *)xmlNode
{
	self = [super init];
    if (self) 	{
		xmlNode_ = xmlNode;
	}
	return self;
}

- (void)dealloc {
    self.xpathError = nil;
}

#pragma mark - navigating methods

- (HTMLNode *)parent
{
	return (xmlNode_->parent) ? [HTMLNode nodeWithXMLNode:xmlNode_->parent] : nil;	
}

- (HTMLNode *)nextSibling
{
	return (xmlNode_->next) ? [HTMLNode nodeWithXMLNode:xmlNode_->next] : nil;
}

- (HTMLNode *)previousSibling 
{
	return (xmlNode_->prev) ? [HTMLNode nodeWithXMLNode:xmlNode_->prev] : nil;	
}

- (HTMLNode *)firstChild
{
	return (xmlNode_->children) ? [HTMLNode nodeWithXMLNode:xmlNode_->children] : nil;	
}

- (HTMLNode *)lastChild
{
	return (xmlNode_->last) ? [HTMLNode nodeWithXMLNode:xmlNode_->last] : nil;
}

- (HTMLNode *)childAtIndex:(NSUInteger)index
{
	NSArray *childrenArray = self.children;
    return (index < [childrenArray count]) ? [childrenArray objectAtIndex:index] : nil;
}

- (NSArray *)children
{
	xmlNode *currentNode = NULL;
	NSMutableArray *array = [NSMutableArray array]; 
    
	for (currentNode = xmlNode_->children; currentNode; currentNode = currentNode->next) {	
		HTMLNode *node = [[HTMLNode alloc] initWithXMLNode:currentNode];
		[array addObject:node];
	}
	
	return array;
}

- (NSUInteger)childCount
{
    return (NSUInteger)xmlChildElementCount(xmlNode_);
}

#pragma mark - attributes and values of current node (self)

- (NSString *)attributeForName:(NSString *)name
{	
    NSString *result = nil;
    
    xmlChar *attributeValue = xmlGetProp(xmlNode_, BAD_CAST [name UTF8String]);
    if (attributeValue) {
        result = [NSString stringWithUTF8String:(const char *)attributeValue];
        xmlFree(attributeValue);
    }
    return result;
}

- (NSDictionary *)attributes
{
    if (self.isDocumentNode) return nil;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *value;
    
    for (xmlAttrPtr attr = xmlNode_->properties; attr ; attr = attr->next) {
        value = [NSString stringWithUTF8String:(const char *)attr->children->content];
        [result setValue:value forKey:[NSString stringWithUTF8String:(const char *)attr->name]];
    }
    
    return result;
}


- (NSString *)tagName
{
    return (self.isDocumentNode) ? nil : [NSString stringWithUTF8String:(const char *) xmlNode_->name];
}

- (NSString *)className // actually classValue
{
	return [self attributeForName:kClassKey];
}

- (NSString *)hrefValue
{
	return [self attributeForName:@"href"];
}

- (NSString *)srcValue
{
	return [self attributeForName:@"src"];
}

- (NSInteger )integerValue
{
    if (XML_CHECK_CONTENT(xmlNode_)) {
		return (NSInteger)atoi((const char*)xmlNode_->children->content);
	}
    
    return 0;
}

- (double )doubleValue
{
    if (XML_CHECK_CONTENT(xmlNode_)) {
        return atof((const char*)xmlNode_->children->content);
    }
    
    return 0.0;
}

// ISO 639 identifier e.g. en_US or fr_CH
- (double )doubleValueOfString:(NSString *)string forLocaleIdentifier:(NSString *)identifier 
{
    NSNumberFormatter * numberFormatter = [[NSNumberFormatter alloc] init];
    if (identifier) {
        NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:identifier];
        [numberFormatter setLocale:locale];
    }
    [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
    NSNumber *number = [numberFormatter numberFromString:string];
    return [number doubleValue];
}

- (double )doubleValueForLocaleIdentifier:(NSString *)identifier
{
    return [self doubleValueOfString:self.stringValue forLocaleIdentifier:identifier];
}

- (double )contentDoubleValueForLocaleIdentifier:(NSString *)identifier
{
    return [self doubleValueOfString:self.textContent forLocaleIdentifier:identifier];
}

// date format e.g. @"yyyy-MM-dd 'at' HH:mm" --> 2001-01-02 at 13:00
- (NSDate *)dateValueFromString:(NSString *)string format:(NSString *)dateFormat timeZone:(NSTimeZone *)timeZone
{
    NSDate *formattedDate;
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:dateFormat];
    [dateFormatter setTimeZone:timeZone];
    formattedDate = [dateFormatter dateFromString:string];
    
    return formattedDate;
}

- (NSDate *)dateValueForFormat:(NSString *)dateFormat timeZone:(NSTimeZone *)timeZone
{
    return [self dateValueFromString:self.stringValue format:dateFormat timeZone:timeZone];
}

- (NSDate *)contentDateValueForFormat:(NSString *)dateFormat timeZone:(NSTimeZone *)timeZone
{
    return [self dateValueFromString:self.textContent format:dateFormat timeZone:timeZone];
}

- (NSDate *)dateValueForFormat:(NSString *)dateFormat
{
    return [self dateValueForFormat:dateFormat timeZone:[NSTimeZone systemTimeZone]];
}

- (NSDate *)contentDateValueForFormat:(NSString *)dateFormat
{
    return [self contentDateValueForFormat:dateFormat timeZone:[NSTimeZone systemTimeZone]];
}

- (NSString *)rawStringValue
{
    xmlNode *child = xmlNode_->children;
    if (child && child->type != XML_ELEMENT_NODE) {
        xmlChar *string = child->content;
        if (string) {
            return [NSString stringWithUTF8String:(const char *)string];
        }
    }
    
    return nil;
}

- (NSString *)stringValue
{
    return [self.rawStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)stringValueCollapsingWhitespace;
{
    return [self.stringValue collapseWhitespaceAndNewLine];
}

- (NSString *)HTMLString
{
    NSString *string = nil;
    
    if (xmlNode_) {
        xmlBufferPtr buffer = xmlBufferCreate();
        if (buffer) {
            int result = xmlNodeDump(buffer, NULL, xmlNode_, 0, 0);
            if (result > -1) {
                string = [[NSString alloc] initWithBytes:(xmlBufferContent(buffer))
                                                   length:(xmlBufferLength(buffer))
                                                 encoding:NSUTF8StringEncoding];
            }
            xmlBufferFree(buffer);
        }
    }
    
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

void textContentOfChildren(xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    xmlNode *currentNode;
    NSString *content;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {
        content = textContent(currentNode);
        if (content) {
            if ([content isEqualToString:@""])
                [array addObject:content];
            else {
                content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (![content isEqualToString:@""]) [array addObject:content];
            }
        }
        if (recursive) textContentOfChildren(currentNode->children, array, recursive);
    }
}


- (NSArray *)textContentOfChildren
{
    NSMutableArray *array = [NSMutableArray array];
    textContentOfChildren(xmlNode_->children, array, NO);
    return array;
}

- (NSArray *)textContentOfDescendants
{
    NSMutableArray *array = [NSMutableArray array];
    textContentOfChildren(xmlNode_->children, array, YES);
    return array;
}


- (xmlElementType )elementType
{
    return xmlNode_->type;
}

- (BOOL)isAttributeNode
{
    return xmlNode_->type == XML_ATTRIBUTE_NODE;
}

- (BOOL)isDocumentNode
{
    return xmlNode_->type == XML_HTML_DOCUMENT_NODE;
}

- (BOOL)isElementNode
{
    return xmlNode_->type == XML_ELEMENT_NODE;
}

- (BOOL)isTextNode
{
    return xmlNode_->type == XML_TEXT_NODE;
}


#pragma mark - attributes and values of current node and its descendants (descendant-or-self)

NSString * textContent(xmlNode *node)
{
    xmlChar *contents = xmlNodeGetContent(node);
    
    if (contents) {
        NSString *string = [NSString stringWithUTF8String:(const char *)contents];
        xmlFree(contents);
        return string;
    }
    
    return nil;
}

- (NSString *)rawTextContent
{
    return textContent(xmlNode_);
}

- (NSString *)textContent
{
    return [textContent(xmlNode_) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)textContentCollapsingWhitespace;
{
    return [self.textContent collapseWhitespaceAndNewLine];
}


- (NSString *)HTMLContent 
{	
    NSString *result = nil;
    xmlBufferPtr xmlBuffer = xmlBufferCreateSize(DUMP_BUFFER_SIZE);
    xmlOutputBufferPtr outputBuffer = xmlOutputBufferCreateBuffer(xmlBuffer, NULL);
    
    htmlNodeDumpOutput(outputBuffer, xmlNode_->doc, xmlNode_, (const char *)xmlNode_->doc->encoding);
    xmlOutputBufferFlush(outputBuffer);
    
    if (xmlBuffer->content) {
        result = [[NSString alloc] initWithBytes:(const void *)xmlBufferContent(xmlBuffer) 
                                           length:xmlBufferLength(xmlBuffer) 
                                         encoding:NSUTF8StringEncoding];
    }
    
    xmlOutputBufferClose(outputBuffer);
    xmlBufferFree(xmlBuffer);
    
    return result;
}


#pragma mark - query methods

HTMLNode * childWithAttributeValueMatches(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, BOOL recursive)
{
    xmlNode *currentNode = NULL;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {
        
        for (xmlAttrPtr attr = currentNode->properties; attr; attr = attr->next) {
            if (xmlStrEqual(attr->name, attrName)) {                    
                xmlNode * child = attr->children;
                if (child && xmlStrEqual(child->content, attrValue))
                    return [HTMLNode nodeWithXMLNode:currentNode];
            }
        }
        
        if (recursive) {
            HTMLNode *subNode = childWithAttributeValueMatches(attrName, attrValue, currentNode->children, recursive);
            if (subNode) 
                return subNode;
            
        }
    }
    
    return NULL;
}

HTMLNode * childWithAttributeValueContains(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, BOOL recursive)
{
    xmlNode *currentNode = NULL;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {
        
        for (xmlAttrPtr attr = currentNode->properties; attr; attr = attr->next) {
            if (xmlStrEqual(attr->name, attrName)) {                    
                xmlNode * child = attr->children;
                if (child && xmlStrstr(child->content, attrValue) != NULL)
                    return [HTMLNode nodeWithXMLNode:currentNode];
            }
        }
        
        if (recursive) {
            HTMLNode *subNode = childWithAttributeValueContains(attrName, attrValue, currentNode->children, recursive);
            if (subNode) 
                return subNode;
            
        }
    }
    return NULL;
}

void childrenWithAttributeValueMatches(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    if (attrName == NULL) return;
    
    xmlNode *currentNode;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {	
        
        for (xmlAttrPtr attr = currentNode->properties; attr; attr = attr->next) {
            if (xmlStrEqual(attr->name, attrName)) {
                xmlNode * child = attr->children;
                if (child && xmlStrEqual(child->content, attrValue)) {
                    HTMLNode *matchingNode = [[HTMLNode alloc] initWithXMLNode:currentNode];
                    [array addObject:matchingNode];
                    break;
                }
            }
        }
        
        if (recursive) childrenWithAttributeValueMatches(attrName, attrValue, currentNode->children, array, recursive);
    }	
}

void childrenWithAttributeValueContains(const xmlChar * attrName, const xmlChar * attrValue, xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    if (attrName == NULL) return;
    
    xmlNode *currentNode;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {
        
        for (xmlAttrPtr attr = currentNode->properties; attr; attr = attr->next) {
            
            if (xmlStrEqual(attr->name, attrName)) {
                xmlNode * child = attr->children;
                if (child && xmlStrstr(child->content, attrValue) != NULL) {
                    HTMLNode *matchingNode = [[HTMLNode alloc] initWithXMLNode:currentNode];
                    [array addObject:matchingNode];
                    break;
                }
            }
        }
        
        if (recursive) childrenWithAttributeValueContains(attrName, attrValue, currentNode->children, array, recursive);
    }	
}

- (HTMLNode *)descendantWithAttribute:(NSString *)attributeName valueMatches:(NSString *)attributeValue 
{
    return childWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, YES);
}

- (HTMLNode *)childWithAttribute:(NSString *)attributeName valueMatches:(NSString *)attributeValue 
{
    return childWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, NO);
}

- (HTMLNode *)descendantWithAttribute:(NSString *)attributeName valueContains:(NSString *)attributeValue 
{
    return childWithAttributeValueContains(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, YES);
}

- (HTMLNode *)childWithAttribute:(NSString *)attributeName valueContains:(NSString *)attributeValue 
{
    return childWithAttributeValueContains(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, NO);
}

- (NSArray *)descendantsWithAttribute:(NSString *)attributeName valueMatches:(NSString *)attributeValue 
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenWithAttribute:(NSString *)attributeName valueMatches:(NSString *)attributeValue 
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, array, NO);
    return array;
}

- (NSArray *)descendantsWithAttribute:(NSString *)attributeName valueContains:(NSString *)attributeValue 
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueContains(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenWithAttribute:(NSString *)attributeName valueContains:(NSString *)attributeValue 
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueContains(BAD_CAST [attributeName UTF8String], BAD_CAST [attributeValue UTF8String], xmlNode_->children, array, NO);
    return array;
}

- (HTMLNode *)descendantWithAttribute:(NSString *)attributeName
{
    return childWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], NULL, xmlNode_->children, YES);
}

- (HTMLNode *)childWithAttribute:(NSString *)attributeName
{
    return childWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], NULL, xmlNode_->children, NO);
}

- (NSArray *)descendantsWithAttribute:(NSString *)attributeName
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], NULL, xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenWithAttribute:(NSString *)attributeName
{
    NSMutableArray *array = [NSMutableArray array];
    childrenWithAttributeValueMatches(BAD_CAST [attributeName UTF8String], NULL, xmlNode_->children, array, NO);
    return array;
}


- (HTMLNode *)descendantWithClass:(NSString *)classValue
{	
    return childWithAttributeValueMatches(BAD_CAST "class", BAD_CAST [classValue UTF8String], xmlNode_->children, YES);
}

- (HTMLNode *)childWithClass:(NSString *)classValue
{	
    return childWithAttributeValueMatches(BAD_CAST "class", BAD_CAST [classValue UTF8String], xmlNode_->children, NO);
}

- (NSArray *)descendantsWithClass:(NSString *)classValue
{	
    return [self descendantsWithAttribute:kClassKey valueMatches:classValue];
}

- (NSArray *)childrenWithClass:(NSString *)classValue
{	
    return [self childrenWithAttribute:kClassKey valueMatches:classValue];
}

HTMLNode * childOfTagValueMatches(const xmlChar * tagName, const xmlChar * value, xmlNode * node, BOOL recursive)
{
    xmlNode *currentNode, *childNode;
    const xmlChar *childName;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) 	{
        if (xmlStrEqual(currentNode->name, tagName)) {
            childNode = currentNode->children;
            childName = (childNode) ? childNode->content : NULL;
            if (childName && xmlStrEqual(childName, value)) {
                return [HTMLNode nodeWithXMLNode:currentNode];
            }
        }
        if (recursive) {
            HTMLNode *subNode = childOfTagValueMatches(tagName, value, currentNode->children, recursive);
            if (subNode) 
                return subNode;
            
        }
    }	
    
    return nil;
}

HTMLNode * childOfTagValueContains(const xmlChar * tagName, const xmlChar * value, xmlNode * node, BOOL recursive)
{
    xmlNode *currentNode, *childNode;
    const xmlChar *childName;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) 	{
        if (xmlStrEqual(currentNode->name, tagName)) {
            childNode = currentNode->children;
            childName = (childNode) ? childNode->content : NULL;
            if (childName && xmlStrstr(childName, value) != NULL) {
                return [HTMLNode nodeWithXMLNode:currentNode];
            }
        }
        if (recursive) {
            HTMLNode *subNode = childOfTagValueContains(tagName, value, currentNode->children, recursive);
            if (subNode) 
                return subNode;
            
        }
    }	
    
    return nil;
}

- (HTMLNode *)descendantOfTag:(NSString *)tagName valueMatches:(NSString *)value
{
    return childOfTagValueMatches(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, YES);
}

- (HTMLNode *)childOfTag:(NSString *)tagName valueMatches:(NSString *)value
{
    return childOfTagValueMatches(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, NO);
}

- (HTMLNode *)descendantOfTag:(NSString *)tagName valueContains:(NSString *)value
{
    return childOfTagValueContains(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, YES);
}

- (HTMLNode *)childOfTag:(NSString *)tagName valueContains:(NSString *)value
{
    return childOfTagValueContains(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, NO);
}


void childrenOfTagValueMatches(const xmlChar * tagName, const xmlChar * value, xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    if (tagName == NULL) return;
    
    xmlNode *currentNode, *childNode;
    const xmlChar *childName;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) 	{
        if (xmlStrEqual(currentNode->name, tagName)) {
            childNode = currentNode->children;
            childName = (childNode) ? childNode->content : NULL;
            if (childName && xmlStrEqual(childName, value)) {
                HTMLNode * matchingNode = [[HTMLNode alloc] initWithXMLNode:currentNode];
                [array addObject:matchingNode];
            }
        }
        if (recursive) childrenOfTagValueMatches(tagName, value, currentNode->children, array, recursive);
    }	
}

void childrenOfTagValueContains(const xmlChar * tagName, const xmlChar * value, xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    if (tagName == NULL) return;
    
    xmlNode *currentNode, *childNode;
    const xmlChar *childName;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) 	{
        if (xmlStrEqual(currentNode->name, tagName)) {
            childNode = currentNode->children;
            childName = (childNode) ? childNode->content : NULL;
            if (childName && xmlStrstr(childName, value) != NULL) {
                HTMLNode * matchingNode = [[HTMLNode alloc] initWithXMLNode:currentNode];
                [array addObject:matchingNode];
            }
        }
        if (recursive) childrenOfTagValueContains(tagName, value, currentNode->children, array, recursive);
    }	
}


- (NSArray *)descendantsOfTag:(NSString *)tagName valueMatches:(NSString *)value
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTagValueMatches(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenOfTag:(NSString *)tagName valueMatches:(NSString *)value
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTagValueMatches(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, array, NO);
    return array;
}

- (NSArray *)descendantsOfTag:(NSString *)tagName valueContains:(NSString *)value
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTagValueContains(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenOfTag:(NSString *)tagName valueContains:(NSString *)value
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTagValueContains(BAD_CAST [tagName UTF8String], BAD_CAST [value UTF8String], xmlNode_->children, array, NO);
    return array;
}



HTMLNode * childOfTag(const xmlChar * tagName, xmlNode * node, BOOL recursive)
{
    xmlNode *currentNode;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) 	{				
        if (currentNode->name && xmlStrEqual(currentNode->name, tagName)) {
            return [HTMLNode nodeWithXMLNode:currentNode];
        }
        if (recursive) {
            HTMLNode *subNode = childOfTag(tagName, currentNode->children, recursive);
            if (subNode) 
                return subNode;
            
        }
    }	
    
    return nil;
}

- (HTMLNode *)descendantOfTag:(NSString *)tagName
{
    return (tagName) ? childOfTag(BAD_CAST [tagName UTF8String], xmlNode_->children, YES) : nil;
}

- (HTMLNode *)childOfTag:(NSString *)tagName
{
    return (tagName) ? childOfTag(BAD_CAST [tagName UTF8String], xmlNode_->children, NO) : nil;
}


void childrenOfTag(const xmlChar * tagName, xmlNode * node, NSMutableArray * array, BOOL recursive)
{
    if (tagName == NULL) return;
    
    xmlNode *currentNode;
    
    for (currentNode = node; currentNode; currentNode = currentNode->next) {				
        if (currentNode->name && xmlStrEqual(currentNode->name, tagName)) {
            HTMLNode * matchingNode = [[HTMLNode alloc] initWithXMLNode:currentNode];
            [array addObject:matchingNode];
        }
        
        if (recursive) childrenOfTag(tagName, currentNode->children, array, recursive);
    }	
}

- (NSArray *)descendantsOfTag:(NSString *)tagName
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTag(BAD_CAST [tagName UTF8String], xmlNode_->children, array, YES);
    return array;
}

- (NSArray *)childrenOfTag:(NSString *)tagName
{
    NSMutableArray *array = [NSMutableArray array];
    childrenOfTag(BAD_CAST [tagName UTF8String], xmlNode_->children, array, NO);
    return array;
}


#pragma mark - description
// includes type, name , number of children, attributes and the first 80 characters of raw content
- (NSString *)description
{
    return [NSString stringWithFormat:@"type: %d - name: %@ - number of children: %lu\nattributes: %@\nHTML: %@", 
            self.elementType,  self.tagName, self.childCount, self.attributes, self.HTMLString];   
}

@end
