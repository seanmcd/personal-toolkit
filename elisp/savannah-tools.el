;;; This is a suite of tools that I created for a project at DesertNet. What I
;;; needed to do was take an XML file that resulted from a `sqldump -X` and an
;;; XML file containing metadata about some images, then combine them into a
;;; single XML file with the same data in a different tag-tree so that our CMS
;;; could easily ingest the resulting file. Luckily for me, since the client
;;; information was all in those external files, I ended up with a utility file
;;; that I could make public.  So I'm making it public as evidence that I can
;;; find my own butt with both hands in Emacs Lisp.

;; Lookup tables

(defvar savannah-authors-alist
  ;; Business information redacted.
  '(("staff" . "123")
    ("Joan Surname" . "456")
    ("Miranda Zero" . "789")))

(defvar savannah-authors-special-cases-alist
  ;; Business information redacted.
  '(("jsmith" . "Jane Smith")
    ("zgarcia" . "Zuryanna Garcia")))

(defvar savannah-issue-list
  ;; Business information redacted.
  '((("start" . ("2009-03-11" 1236754800)) ;; ( Human-readable . epoch-seconds)
     ("stop" . ("2009-03-17" 1237273200))
     ("oid" . "123"))
    (("start" . ("2009-03-18" 1237359600))
     ("stop" . ("2009-03-24" 1237878000))
     ("oid" . "456"))
    (("start" . ("2009-03-25" 1237964400))
     ("stop" . ("2009-03-31" 1238482800))
     ("oid" . "789"))))

;; Conversion functions

(defun savannah-seconds (date)
  (string-to-number (shell-command-to-string (concat "gdate --date '" date "' +'%s'"))))

(defun savannah-date-to-issue-id (date)
  (interactive)
  (let ((issue-list savannah-issue-list)
        (seconds-date (savannah-seconds date))
        (found-issue nil))
    (dolist (maybe-issue issue-list match)
      (let ((this-start (caddr (assoc "start" maybe-issue)))
            (this-stop (caddr (assoc "stop" maybe-issue)))
            (oid (cdr (assoc "oid" maybe-issue))))
        (when
            (and (< seconds-date this-stop) (> seconds-date this-start))
          (setq match oid))))))

(defun savannah-author-to-oid (author-name)
  ;; just a no-op when no argument provided.
  (when (assoc
         author-name savannah-authors-special-cases-alist)
    (setq author-name
          (cdr (assoc author-name savannah-authors-special-cases-alist))))
  (if (assoc
       author-name savannah-authors-alist)
      (cdr (assoc author-name savannah-authors-alist))
    nil))

(defun savannah-get-oid-from-legacy-author_id (id)
  ;; Really, this should be another defvar - artifact from when I was still
  ;; figuring out the problem space.
  (interactive)
  (let ((author-alist
  ;; Business information redacted.
         '(("233" . "The Wizard of Yendor")
           ("264" . "Wilt Chamberlain"))))
    (when (assoc id author-alist)
      (savannah-author-to-oid (cdr (assoc id author-alist))))))

;; Image-retrieval functions

(defun savannah-go-to-matching-image (oid)
  (let ((id-string (concat "<ContentID>" oid "</ContentID>")))
    (message "searching for image for oid:%s ..." oid)
    (when (search-forward id-string nil t) ;; move point to end of the found string.
      (nxml-backward-up-element) ;; put point at the beginning of <Image>
      (message "found an image for oid:%s" oid)
      t)
    ))

(defun savannah-kill-image-at-point (&optional dry-run)
  (let ((initial-point (point)))
    (nxml-forward-element 1)
    (unless dry-run
      (kill-region initial-point (point)))))

(defun savannah-grab-matching-image-from-buffer (oid image-buffer)
  (setq savannah-image-found nil)
  (with-current-buffer image-buffer
    (beginning-of-buffer)
    (when (savannah-go-to-matching-image oid)
      (savannah-kill-image-at-point)
      t)))

(defun savannah-yank-after-body (&optional comment-out-id)
  ;; assumes that there's an Image at the top of the kill ring.
  (search-backward "<object id=") ;; beginning of current object
  (search-forward "</Body>")
  (newline-and-indent)
  (yank)
  (when comment-out-id
    (search-backward "<ContentId>")
    (let ((initial-point (point)))
      (nxml-forward-element)
      (comment-region initial-point (point)))))

(defun savannah-grab-all-images-for-given-oid (oid image-buffer)
  ;; (interactive "sSearch for images matching this ID: ")
  (let ((continue-flag t))
    (while continue-flag
      (if (savannah-grab-matching-image-from-buffer oid image-buffer)
          (savannah-yank-after-body t)
        (setq continue-flag nil))))
  )

;; XML retrieval/parsing

(defun get-field-from-row-sexp (field row)
  ;; Note: if there is no field FIELD or if that field has an empty string as
  ;; content, this function returns nil. Field nodes are like `(field ((name
  ;; . ,field-name)) ,field-data) and we want field-data, which may be nil.
  (let
      ((field-payload
        (car
         (remove-if-not #'stringp
          (car
           (remove-if #'null
            (mapcar
             (lambda (node)
               (when (and (listp node)
                          (assoc `(name . ,field) node))
                 node))
             row)))))))
    ;; (message "Found (length %s): %s" (length field-payload) (pp-to-string field-payload))
    field-payload))

(defun savannah-parse-tags (text-blob)
;; Thank you Stack Overflow: http://stackoverflow.com/a/12836972/244494
  (unless (stringp text-blob)
    (error "Uh-oh, bad value in parsing tags: %s" (pp-to-string text-blob)))
  (let ((i 0)
        ;; (multi-tag-blob (replace-regexp-in-string "&quot;" "'" text-blob))
        ;; (multi-tag-blob (replace-regexp-in-string "\"" "'" text-blob))
        (multi-tag-blob text-blob)
        result current quotep escapedp word) ;; start as nil
    (while (< i (length multi-tag-blob))
      (setq current (aref multi-tag-blob i))
      (cond
       ((and (char-equal current ?\ )
             (not quotep))
        (when word (push word result))
        (setq word nil escapedp nil))
       ((and (char-equal current ?\")
             (not escapedp)
             (not quotep))
        (setq quotep t escapedp nil))
       ((and (char-equal current ?\")
             (not escapedp))
        (push word result)
        (setq quotep nil word nil escapedp nil))
       ((char-equal current ?\\)
        (when escapedp (push current word))
        (setq escapedp (not escapedp)))
       (t (setq escapedp nil)
        (push current word)))
      (incf i))
    (when quotep
      (error (format "Unbalanced quotes at %d"
                     (- (length multi-tag-blob) (length word)))))
    (when word (push result word))
    (mapcar (lambda (x) (coerce (reverse x) 'string))
            (reverse result))))

(defun savannah-re-escape-xml (xml-string)
  (let ((replacement-pairs
         '(("&" . "&amp;")
           (">" . "&gt;")
           ("<" . "&lt;"))))
    (loop for pair in replacement-pairs
          do (setq xml-string
                   (replace-regexp-in-string (car pair) (cdr pair) xml-string))
          finally return xml-string)))

(defun make-foundation-object-sexp (xml-blob)

  (defmacro gffrs (field)
    ;; Not the most graceful way to handle this. A better macro is almost
    ;; certainly possible, but I'm not currently sure how to write it.
    `(get-field-from-row-sexp ,field xml-blob))

  (let ((oid (gffrs "id"))
        (category (gffrs "Category"))
        (author
         (cond
          ;; In the source DB, the query "select byline1, byline2, header as
          ;; Headline from news_article where (byline1 not like '') and
          ;; (byline2 not like '');" results in an empty set, which lets us use
          ;; this relatively easy case statement.
          ((> 1 (length (gffrs "byline1")))
           (savannah-author-to-oid (gffrs "byline1")))
          ((> 1 (length (gffrs "byline2")))
           (savannah-author-to-oid (gffrs "byline2")))
          ((> 1 (length (gffrs "author_id")))
           (savannah-get-oid-from-legacy-author_id (gffrs "author_id")))
          (t "")))
        (headline (gffrs "Headline"))
        (subheadline (gffrs "Subheadline"))
        (body
         (let ((primary (gffrs "Body1"))
               (secondary (gffrs "Body2")))
           (when secondary
             (setq primary (concat primary "\n&lt;hr&gt;\n" secondary)))
           primary))
        (content-feature
         (if (string-equal (gffrs "ContentFeature") "1")
             "2130628" ""))
        (access-count (gffrs "AccessCount"))
        (release-date (gffrs "ReleaseDate"))
        (issue (savannah-date-to-issue-id (gffrs "ReleaseDate")))
        (status
         (if (string-equal (gffrs "Status") "1")
             "Offline" "Live")) ;; wonky because the source data is a "hide" bit
        (comment-status
         (if (string-equal (gffrs "CommentStatus") "1")
             "Members Only" "Closed"))
        (tags (if (gffrs "Tags")
                  (savannah-parse-tags (gffrs "Tags"))
                ""))
        )
    (list oid
          `(("Category" . ,category)
            ("Author" . ,author)
            ("Headline" . ,headline)
            ("Subheadline" . ,subheadline)
            ("Body" . ,body)
            ("ContentFeature" . ,content-feature)
            ("AccessCount" . ,access-count)
            ("ReleaseDate" . ,release-date)
            ("Issue" . ,issue)
            ("Status" . ,status)
            ("CommentStatus" . ,comment-status)
            ("Tags" ,tags)))
    ))

(defun savannah-turn-row-to-object ()
  (interactive)
    (search-forward "<row>")
    (nxml-backward-up-element)
    (setq *sav-current-tag* (xml-parse-tag))
    (setq *sav-current-sexp*
          (make-foundation-object-sexp *sav-current-tag*))
    ;; (message "Proof of concept: %s" *sav-current-sexp*)
    (identity *sav-current-sexp*)
)

(defun savannah-alist-to-xml (input-alist)
  (let ((tag-name (car input-alist))
        (tag-content (if (listp (cdr input-alist))
                         (elt input-alist 1)
                       (cdr input-alist))))
    (if (not (listp tag-content))
        (format "<%s>%s</%s>\n"
                tag-name (savannah-re-escape-xml tag-content) tag-name)
      ;; (message "Tags found: %s" (pp-to-string tag-content))
      (loop for tag-item in tag-content
            collecting (format "<%s>%s</%s>\n" tag-name tag-item tag-name)
            into list-of-tags
            finally return
            (apply #'concat
                   (remove-if
                    (lambda (s) (string-equal "none" s))
                      list-of-tags))))))

(defun foundation-object-to-xml (oid attribute-list)
  (let ((object-begin-tag (format "<object id=\"%s\">" oid))
        (object-end-tag "</object>")
        (xml-blob nil))
    (setq xml-blob
          (concat object-begin-tag "\n"))
    (while attribute-list
      (setq next-attribute (pop attribute-list))
      (setq xml-blob
            (concat xml-blob (savannah-alist-to-xml next-attribute))))
    (setq xml-blob
          (concat xml-blob object-end-tag))))

(defun savannah-row-to-xml ()
  (interactive)
  (setq parsed-row (savannah-turn-row-to-object))
  (let ((oid (elt parsed-row 0))
        (attributes (elt parsed-row 1)))
    (foundation-object-to-xml oid attributes)
    ))

(defun savannah-grab-next-xml-object (row-buffer image-buffer)
  ;; assume that we start in the buffer we want to write to
  (interactive "bRow buffer: \nbImage buffer: ")
  (let ((write-buffer (current-buffer)))
    ;; Not using save-excursion because we need to, effectively, iterate over
    ;; the row-buffer's contents.
    (switch-to-buffer row-buffer)
    (setq *sav-current-xml* (savannah-row-to-xml)) ;; watch out, this moves point
    (let ((end-point (point)))
      (nxml-backward-element)
      (kill-region (point) end-point))
    (switch-to-buffer write-buffer)
    (insert *sav-current-xml*)
    (newline-and-indent)
    (search-backward "<object id=")
    (next-line)
    (let ((oid (car *sav-current-sexp*)))
      (savannah-grab-all-images-for-given-oid oid image-buffer))
    (search-backward "<object id=")
    (let ((start-point (point)))
      (nxml-forward-element)
      (indent-region start-point (point)))
    (next-line)))

;; Once things are set up, run 'savannah-grab-next-xml-object as many times as
;; it takes to slurp up the input files.
