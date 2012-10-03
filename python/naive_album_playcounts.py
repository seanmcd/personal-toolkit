#-*- coding: utf-8 -*-
#!/usr/bin/python

""" A script that investigates my iTunes Music Library xml and gives me a list
    of the albums whose songs I have listened to the most. Each album's score
    is the sum of the playcounts of the songs in that album. I created this
    because this is information that iTunes doesn't expose in its own UI.

    Don't use this directly on your iTunes library XML, use it on a copy.

    This script assumes that it's running on Python 2.6+, that it's in the same
    directory as a copy of the 'iTunes Music Library.xml' file, and that lxml
    is installed.

    The formatting of the results will look cruddy (show HTML entity codes) for
    albums with some non-alphnumeric characters in their names - for example
    the Basshunter album 'LOL <(^^,)>'.

    The major outstanding issue with this script is that it takes the naive
    approach to XML parsing - it loads the entire XML document into memory and
    constructs a DOM from it. My iTunes library is bigger than most since it
    tracks ~30,000 entries, and this script takes most of a minute to comb
    through it, so there's definitely room for improvement, but the flaw isn't
    critical. A future version should definitely switch to SAX-style parsing,
    though.

    There are also definitely some style and organization issues that could be
    fixed, which would make a good exercise for the future.
"""

import lxml
from lxml import etree

# Data will go in this global. Nothing fancy.
giant_list = {}

class Album(object):
    """Represents an album that we're interested in."""
    def __init__(self, name, artist):
        """Create an album by providing name and artist. """
        self.name = name
        self.artist = artist
        self.song_list = []

    def add_song(self, title, playcount):
        """String, integer expected"""
        self.song_list.append((title, int(playcount)))

    def top_song(self):
        current_songs = sorted(self.song_list, key = lambda song: song[1], reverse = True)
        top_song = current_songs[0]
        return top_song

    def total_plays(self):
        total = 0
        for s in self.song_list:
            total += s[1]
        print "Total song playcount on {0}: {1}".format(self.name, total)
        return total

def playcount_sort(giant_list):
    """Hand this function a list of Album objects."""
    giant_list.sort(key = lambda album: album.total_plays(), reverse = True)
    top_ten_list = giant_list[0:9]
    return top_ten_list

def show_final(top_list):
    for album in top_list:
        print "The album {0} has a total of {1} plays.".format(album.name, album.total_plays())
        print "The most-played song on {0} is {1} with {2} plays.".format(album.name, album.top_song()[0], album.top_song()[1])

def comb_library():
    try:
        itunes = etree.parse('itunes.xml')
        # Hello, memory-intensive operation!
    except Exception, e:
        print e
        # TODO: Go from near-zero error handling to substantial/informative error handling.
        exit()

    tracks = itunes.xpath('//plist/dict/key[contains(text(),"Tracks")]/following-sibling::dict[1]/child::dict')
    # .xpath('//plist/dict/key[contains(text(),"Tracks")]/following-sibling::dict[1]/child::dict')
    # An XPath expression that captures the 'Tracks' dict from the iTunes xml,
    # omitting the <key> children of that dict.

    # Now we have something to work with.
    for track in tracks:
        song_data = {}
        for field in track:
            if field.text == 'Album': song_data['Album'] = field.getnext().text.encode('utf-8')
            if field.text == 'Name': song_data['Name'] = field.getnext().text.encode('utf-8')
            if field.text == 'Artist': song_data['Artist'] = field.getnext().text.encode('utf-8')
            if field.text == 'Album Artist': song_data['Album Artist'] = field.getnext().text.encode('utf-8')
            if field.text == 'Play Count': song_data['Play Count'] = field.getnext().text.encode('utf-8')

        # Reject songs with missing data.
        broken = None
        for field in ['Album', 'Artist', 'Play Count']:
            # Reject songs whose album name is zero-length or similarly
            # problematic.
            try:
                if len(song_data[field]) < 0:
                    broken = 'broken'
            except KeyError:
                broken = 'broken'
        if broken: continue

        # Fiddle to compensate for "Album Artist" data not always being present.
        if 'Album Artist' not in song_data.keys():
            song_data['Album Artist'] = song_data['Artist']

        # Add songs to the giant list.
        album_id = "{0}by{1}".format(song_data['Album'], song_data['Album Artist'])
        song_data['album_and_artist'] = album_id
        if song_data['album_and_artist'] not in giant_list.keys():
            giant_list[album_id] = Album(song_data['Album'], song_data['Artist'])
        giant_list[album_id].add_song(song_data['Name'], song_data['Play Count'])

    medium_list = []
    for album in giant_list.keys():
        medium_list.append(giant_list[album])
    return medium_list


# Run it!
if __name__ == '__main__':
    my_giant_list = comb_library()
    sorted_list = playcount_sort(my_giant_list)
    show_final(sorted_list)
