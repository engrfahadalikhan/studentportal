import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../services/app_repository.dart';
import '../ui/student_portal_shell.dart';
import 'assessment_models.dart';
import 'paper_generator_models.dart';
import 'paper_generator_pdf_service.dart';

class PaperGeneratorScreen extends StatefulWidget {
  const PaperGeneratorScreen({
    super.key,
    required this.repository,
    required this.teacher,
    required this.onAssessmentCreated,
    this.initialCourseId,
  });

  final AppRepository repository;
  final AssessmentTeacher teacher;
  final ValueChanged<Assessment> onAssessmentCreated;
  final String? initialCourseId;

  @override
  State<PaperGeneratorScreen> createState() => _PaperGeneratorScreenState();
}

class _PaperGeneratorScreenState extends State<PaperGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _teacherController;
  final _subjectController = TextEditingController();
  final _dateTimeController = TextEditingController();
  final _classController = TextEditingController();
  final List<_QuestionInputControllers> _questionControllers = [];

  final List<AssessmentCourse> _selectedCourses = [];
  int _questionCount = 3;
  bool _isGenerating = false;
  bool _isSavingAssessment = false;
  Uint8List? _generatedPdf;
  bool _generatedPdfIsDraft = false;

  @override
  void initState() {
    super.initState();
    _teacherController = TextEditingController(text: widget.teacher.name);
    _syncQuestionCount(_questionCount);
    final courses = widget.repository.coursesForTeacher(widget.teacher);
    final initialCourseId = widget.initialCourseId;
    if (initialCourseId != null) {
      final match = courses.where((c) => c.id == initialCourseId).toList();
      if (match.isNotEmpty) {
        _selectedCourses.add(match.first);
        _refreshCourseDerivedFields();
        return;
      }
    }
    if (courses.isNotEmpty) {
      _selectedCourses.add(courses.first);
      _refreshCourseDerivedFields();
    }
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _subjectController.dispose();
    _dateTimeController.dispose();
    _classController.dispose();
    for (final question in _questionControllers) {
      question.dispose();
    }
    super.dispose();
  }

  void _toggleCourseSelection(AssessmentCourse course) {
    setState(() {
      if (_selectedCourses.contains(course)) {
        _selectedCourses.remove(course);
      } else {
        _selectedCourses.add(course);
      }
      _refreshCourseDerivedFields();
      _generatedPdf = null;
    });
  }

  void _refreshCourseDerivedFields() {
    if (_selectedCourses.isEmpty) {
      _subjectController.text = '';
      _classController.text = '';
      return;
    }
    _subjectController.text = _selectedCourses
        .map((c) => '${c.courseCode} - ${c.courseName}')
        .join(' + ');
    _classController.text = _selectedCourses
        .map((c) => '${c.program} ${c.semester}${c.section}'.trim())
        .toSet()
        .join(', ');
  }

  void _syncQuestionCount(int count) {
    if (count == _questionControllers.length) {
      return;
    }

    if (count > _questionControllers.length) {
      for (var index = _questionControllers.length; index < count; index++) {
        _questionControllers.add(_QuestionInputControllers.seeded(index + 1));
      }
      return;
    }

    final removed = _questionControllers.sublist(count);
    for (final question in removed) {
      question.dispose();
    }
    _questionControllers.removeRange(count, _questionControllers.length);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    DateTime? parsedExistingDate;
    final currentValue = _dateTimeController.text.trim();
    if (currentValue.isNotEmpty) {
      try {
        parsedExistingDate = DateFormat(
          'dd MMM yyyy',
        ).parseStrict(currentValue);
      } catch (_) {
        parsedExistingDate = null;
      }
    }
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: parsedExistingDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    setState(() {
      _dateTimeController.text = DateFormat('dd MMM yyyy').format(pickedDate);
      _generatedPdf = null;
    });
  }

  Future<void> _generatePdf({bool isDraft = false}) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedCourses.isEmpty) {
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    final pdfBytes = await buildExamPdf(_buildPaperData(isDraft: isDraft));

    if (!mounted) {
      return;
    }

    setState(() {
      _generatedPdf = pdfBytes;
      _generatedPdfIsDraft = isDraft;
      _isGenerating = false;
    });
  }

  Future<void> _openSaveDialog() async {
    if (_generatedPdf == null) {
      return;
    }

    await Printing.layoutPdf(
      name: '${_buildExportFileName(isDraft: _generatedPdfIsDraft)}.pdf',
      onLayout: (_) async => _generatedPdf!,
    );
  }

  Future<void> _sharePdf() async {
    if (_generatedPdf == null) {
      return;
    }

    await Printing.sharePdf(
      bytes: _generatedPdf!,
      filename: '${_buildExportFileName(isDraft: _generatedPdfIsDraft)}.pdf',
      subject: 'AUST exam paper',
    );
  }

  Future<void> _pickQuestionImage(_QuestionInputControllers question) async {
    final placement = await _promptImagePlacement();
    if (placement == null || !mounted) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file?.bytes == null || !mounted) {
      return;
    }

    setState(() {
      question.imageBytes = file!.bytes;
      question.imageName = file.name;
      question.imagePlacement = placement;
      _generatedPdf = null;
    });
  }

  Future<QuestionImagePlacement?> _promptImagePlacement() {
    return showDialog<QuestionImagePlacement>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Picture position'),
          content: const Text('Where should the picture appear in the PDF?'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(QuestionImagePlacement.left),
              child: const Text('Left'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(QuestionImagePlacement.center),
              child: const Text('Middle'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(QuestionImagePlacement.right),
              child: const Text('Right'),
            ),
          ],
        );
      },
    );
  }

  void _clearQuestionImage(_QuestionInputControllers question) {
    setState(() {
      question.imageBytes = null;
      question.imageName = null;
      question.imagePlacement = QuestionImagePlacement.center;
      _generatedPdf = null;
    });
  }

  PaperFormData _buildPaperData({bool isDraft = false}) {
    final programs = _selectedCourses
        .map((c) => c.program)
        .where((p) => p.isNotEmpty)
        .toSet()
        .join(', ');
    return PaperFormData(
      teacherName: _teacherController.text.trim(),
      subject: _subjectController.text.trim(),
      dateTime: _dateTimeController.text.trim(),
      className: _classController.text.trim(),
      program: programs.isEmpty
          ? _deriveProgramFromClass(_classController.text)
          : programs,
      questions: _questionControllers
          .map((question) => question.toData())
          .toList(),
      isDraft: isDraft,
    );
  }

  String _deriveProgramFromClass(String className) {
    final trimmed = className.trim();
    if (trimmed.isEmpty) {
      return 'Program';
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.first.trim().isEmpty ? 'Program' : parts.first.trim();
  }

  String _buildExportFileName({bool isDraft = false}) {
    final teacherName = _teacherController.text.trim().isEmpty
        ? 'Instructor'
        : _teacherController.text.trim();
    final className = _classController.text.trim().isEmpty
        ? 'Class'
        : _classController.text.trim();
    final paperName = _subjectController.text.trim().isEmpty
        ? 'Paper'
        : _subjectController.text.trim();

    final baseName = '$teacherName - $className - $paperName';
    return _sanitizeFileName(isDraft ? '$baseName - Draft' : baseName);
  }

  String _sanitizeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'AUST Paper' : cleaned;
  }

  Future<void> _saveAssessmentAndGenerateQr() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedCourses.isEmpty) {
      return;
    }

    setState(() {
      _isSavingAssessment = true;
    });

    final primaryCourse = _selectedCourses.first;
    final assessmentQuestions = _questionControllers
        .map((controller) => controller.toAssessmentQuestion())
        .toList();

    final summedTimeMinutes = assessmentQuestions.fold<int>(
      0,
      (sum, question) => sum + question.timeMinutes,
    );
    final durationMinutes = summedTimeMinutes > 0 ? summedTimeMinutes : 60;

    final titleParts = [
      _subjectController.text.trim(),
      if (_dateTimeController.text.trim().isNotEmpty)
        _dateTimeController.text.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final title = titleParts.isEmpty
        ? 'Generated assessment'
        : titleParts.join(' • ');

    final extraClasses = _selectedCourses.length > 1
        ? '\nCovers classes: ${_classController.text.trim()}.'
        : '';

    final assessment = widget.repository.createAssessment(
      title: title,
      type: AssessmentType.examPaper,
      course: primaryCourse,
      durationMinutes: durationMinutes,
      instructions:
          'Question interpretation is part of the exam. Using unfair means will result in paper cancellation. For each question, read the respective instructions very carefully.$extraClasses',
      questions: assessmentQuestions,
      program: primaryCourse.program,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingAssessment = false;
    });

    widget.onAssessmentCreated(assessment);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final previewHeight = isWide
            ? (constraints.maxHeight - 32).clamp(560.0, 900.0).toDouble()
            : 620.0;
        final formPane = _buildFormPane();
        final previewPane = _buildPreviewPane(previewHeight: previewHeight);

        if (!isWide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [formPane, const SizedBox(height: 16), previewPane],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    flex: 10,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: SingleChildScrollView(child: formPane),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Flexible(flex: 15, child: previewPane),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormPane() {
    final courses = widget.repository.coursesForTeacher(widget.teacher);

    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: PortalColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: PortalColors.softBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: PortalColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assessment Generator',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Build a single-page exam paper with CLO, PLO, subparts and pictures.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PortalColors.subtleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('Paper Details'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _teacherController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Teacher Name (auto)',
                prefixIcon: Icon(Icons.co_present_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD8A8)),
                ),
                child: Text(
                  'No courses are assigned to ${widget.teacher.name} in the local enrollment data.',
                ),
              )
            else
              _buildCourseMultiSelect(courses),
            const SizedBox(height: 12),
            _readOnlyField(
              controller: _subjectController,
              label: 'Subject',
              icon: Icons.menu_book_outlined,
              helperText: 'Auto-filled from selected course.',
            ),
            const SizedBox(height: 12),
            _readOnlyField(
              controller: _classController,
              label: 'Class',
              icon: Icons.school_outlined,
              helperText: 'Auto-filled from selected course.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dateTimeController,
              decoration: InputDecoration(
                labelText: 'Date',
                prefixIcon: const Icon(Icons.calendar_today_outlined),
                hintText: 'Select date',
                suffixIcon: IconButton(
                  onPressed: _pickDateTime,
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
              ),
              onChanged: (_) => setState(() => _generatedPdf = null),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Questions Setup'),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _questionCount,
              decoration: const InputDecoration(
                labelText: 'Total Number of Questions',
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
              ),
              items: List.generate(
                15,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}'),
                ),
              ),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _questionCount = value;
                  _syncQuestionCount(value);
                  _generatedPdf = null;
                });
              },
            ),
            const SizedBox(height: 14),
            for (
              var index = 0;
              index < _questionControllers.length;
              index++
            ) ...[
              _buildQuestionCard(index, _questionControllers[index]),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            _buildActionButtons(),
            const SizedBox(height: 12),
            _buildPdfActionButtons(),
            const SizedBox(height: 14),
            _buildSaveAssessmentButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 360;
        final draftButton = OutlinedButton.icon(
          onPressed: _isGenerating ? null : () => _generatePdf(isDraft: true),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Draft PDF'),
        );
        final generateButton = FilledButton.icon(
          onPressed: _isGenerating ? null : () => _generatePdf(),
          icon: _isGenerating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_rounded),
          label: Text(_isGenerating ? 'Generating...' : 'Generate PDF'),
        );

        if (!useRow) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: draftButton),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: generateButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: draftButton),
            const SizedBox(width: 12),
            Expanded(child: generateButton),
          ],
        );
      },
    );
  }

  Widget _buildPdfActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 360;
        final shareButton = OutlinedButton.icon(
          onPressed: _generatedPdf == null ? null : _sharePdf,
          icon: const Icon(Icons.share_rounded),
          label: const Text('Share PDF'),
        );
        final downloadButton = OutlinedButton.icon(
          onPressed: _generatedPdf == null ? null : _openSaveDialog,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download PDF'),
        );

        if (!useRow) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: shareButton),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: downloadButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: shareButton),
            const SizedBox(width: 12),
            Expanded(child: downloadButton),
          ],
        );
      },
    );
  }

  Widget _buildSaveAssessmentButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSavingAssessment || _selectedCourses.isEmpty
            ? null
            : _saveAssessmentAndGenerateQr,
        style: FilledButton.styleFrom(
          backgroundColor: PortalColors.brandBlue,
          foregroundColor: Colors.white,
        ),
        icon: _isSavingAssessment
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.qr_code_2_outlined),
        label: Text(
          _isSavingAssessment ? 'Saving...' : 'Save Assessment & Generate QR',
        ),
      ),
    );
  }

  Widget _buildPreviewPane({required double previewHeight}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: SizedBox(
        height: previewHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'PDF Preview',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: PortalColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: PortalColors.softBlue,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: PortalColors.blueBorder),
                  ),
                  child: Text(
                    _generatedPdf == null
                        ? 'Awaiting PDF'
                        : _generatedPdfIsDraft
                        ? 'Draft ready'
                        : 'Ready',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PortalColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: PortalColors.cardBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _generatedPdf == null
                      ? _buildPreviewPlaceholder()
                      : PdfPreview(
                          build: (_) async => _generatedPdf!,
                          useActions: false,
                          allowPrinting: false,
                          allowSharing: false,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                          maxPageWidth: 720,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [PortalColors.brandBlue, PortalColors.avatarTeal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.auto_awesome_motion_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No PDF yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: PortalColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: const Text(
                'Fill the questions then tap Generate PDF. A draft watermark is added when you tap Draft PDF.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PortalColors.subtleText, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int index, _QuestionInputControllers question) {
    return Container(
      key: ValueKey('question-${index + 1}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: PortalColors.brandBlue,
                ),
                child: const Icon(
                  Icons.quiz_outlined,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Question ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: PortalColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _editableField(
                  controller: question.numberController,
                  label: 'Question Number',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _editableField(
                  controller: question.marksController,
                  label: 'Marks',
                  enabled: !question.hasSubparts,
                  isRequired: !question.hasSubparts,
                  helperText: question.hasSubparts
                      ? 'Auto total from subparts'
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _editableField(
                  controller: question.timeController,
                  label: 'Time (min)',
                  isRequired: false,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _editableField(
                  controller: question.cloController,
                  label: 'CLO',
                  isRequired: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _editableField(
                  controller: question.ploController,
                  label: 'PLO',
                  isRequired: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _structuredTextField(
            controller: question.textController,
            label: 'Question',
            hintText:
                "Use Enter for new lines, '-' or '1.' for lists, Tab to indent. Don't start with what, where, why, how, brief, explain, etc.",
            minLines: 3,
            maxLines: 6,
            validator: (_) => _questionTextValidator(question),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  question.hasSubparts = !question.hasSubparts;
                  if (!question.hasSubparts) {
                    question.syncSubpartCount(0);
                  } else if (question.subparts.isEmpty) {
                    question.syncSubpartCount(1);
                  }
                  question.updateMarksFromSubparts();
                  _generatedPdf = null;
                });
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                question.hasSubparts
                    ? Icons.check_circle_rounded
                    : Icons.library_add_outlined,
                size: 16,
              ),
              label: Text(question.hasSubparts ? 'Sub parts: On' : 'Sub parts'),
            ),
          ),
          const SizedBox(height: 12),
          _buildOptionsEditor(question),
          if (question.hasSubparts) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(
                      'subpart-count-${index + 1}-${question.subparts.length}',
                    ),
                    initialValue: question.subparts.isEmpty
                        ? 1
                        : question.subparts.length,
                    decoration: const InputDecoration(
                      labelText: 'No. of Subparts',
                    ),
                    items: List.generate(
                      10,
                      (subpartIndex) => DropdownMenuItem(
                        value: subpartIndex + 1,
                        child: Text('${subpartIndex + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        question.syncSubpartCount(value);
                        question.updateMarksFromSubparts();
                        _generatedPdf = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<SubpartPlacement>(
                    initialValue: question.subpartPlacement,
                    decoration: const InputDecoration(
                      labelText: 'Subpart Position',
                    ),
                    items: SubpartPlacement.values
                        .map(
                          (placement) => DropdownMenuItem<SubpartPlacement>(
                            value: placement,
                            child: Text(_subpartPlacementLabel(placement)),
                          ),
                        )
                        .toList(),
                    onChanged: (placement) {
                      if (placement == null) {
                        return;
                      }
                      setState(() {
                        question.subpartPlacement = placement;
                        _generatedPdf = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (
              var subpartIndex = 0;
              subpartIndex < question.subparts.length;
              subpartIndex++
            ) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _structuredTextField(
                      controller:
                          question.subparts[subpartIndex].textController,
                      label: 'Subpart ${_subpartLabel(subpartIndex)}',
                      minLines: 2,
                      maxLines: 4,
                      validator: _subpartValidator,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller:
                          question.subparts[subpartIndex].marksController,
                      decoration: const InputDecoration(labelText: 'Marks'),
                      validator: _requiredValidator,
                      onChanged: (_) {
                        setState(() {
                          question.updateMarksFromSubparts();
                          _generatedPdf = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickQuestionImage(question),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Upload Picture'),
              ),
              if (question.imageName != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${question.imageName!} - ${_imagePlacementLabel(question.imagePlacement)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _clearQuestionImage(question),
                  tooltip: 'Remove picture',
                  icon: const Icon(Icons.cancel_rounded),
                ),
              ],
            ],
          ),
          if (question.imageBytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                question.imageBytes!,
                height: 100,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionsEditor(_QuestionInputControllers question) {
    final optionsCount = question.optionControllers.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalColors.blueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.list_alt_outlined,
                size: 18,
                color: PortalColors.brandBlue,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Possible answers (for MCQ-style)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PortalColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int>(
                  key: ValueKey(
                    'options-count-${question.numberController.text}-$optionsCount',
                  ),
                  initialValue: optionsCount,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'No. of answers',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: List.generate(
                    7,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text('$index'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      question.syncOptionsCount(value);
                      _generatedPdf = null;
                    });
                  },
                ),
              ),
            ],
          ),
          if (optionsCount > 0) ...[
            const SizedBox(height: 10),
            for (
              var optionIndex = 0;
              optionIndex < question.optionControllers.length;
              optionIndex++
            ) ...[
              TextFormField(
                controller: question.optionControllers[optionIndex],
                decoration: InputDecoration(
                  labelText:
                      'Answer ${_optionLetter(optionIndex)}',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                ),
                onChanged: (_) => setState(() => _generatedPdf = null),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  String _optionLetter(int index) {
    if (index < 26) {
      return String.fromCharCode(65 + index);
    }
    return '${index + 1}';
  }

  Widget _buildCourseMultiSelect(List<AssessmentCourse> courses) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Courses (select one or more)',
        prefixIcon: const Icon(Icons.class_outlined),
        helperText: _selectedCourses.isEmpty
            ? 'Pick at least one. Combine multiple for a joint paper.'
            : '${_selectedCourses.length} selected',
        contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: courses.map((course) {
          final selected = _selectedCourses.contains(course);
          return FilterChip(
            label: Text(
              '${course.courseCode} ${course.section} - ${course.courseName}',
              overflow: TextOverflow.ellipsis,
            ),
            selected: selected,
            onSelected: (_) => _toggleCourseSelection(course),
            selectedColor: PortalColors.softBlue,
            checkmarkColor: PortalColors.brandBlue,
            side: BorderSide(
              color: selected
                  ? PortalColors.blueBorder
                  : PortalColors.cardBorder,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _readOnlyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        helperText: helperText,
      ),
    );
  }

  Widget _editableField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    bool isRequired = true,
    String? helperText,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      validator: isRequired ? _requiredValidator : null,
      onChanged: (_) => setState(() => _generatedPdf = null),
    );
  }

  Widget _structuredTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    int minLines = 2,
    int maxLines = 4,
    String? Function(String?)? validator,
  }) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          _insertIndent(controller);
          setState(() => _generatedPdf = null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextFormField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(labelText: label, hintText: hintText),
        validator: validator,
        onChanged: (_) => setState(() => _generatedPdf = null),
      ),
    );
  }

  void _insertIndent(TextEditingController controller) {
    const indent = '    ';
    final value = controller.value;
    final selection = value.selection;

    if (!selection.isValid) {
      controller.text = '${controller.text}$indent';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final text = value.text;
    final replacement = text.replaceRange(start, end, indent);
    final offset = start + indent.length;

    controller.value = value.copyWith(
      text: replacement,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: PortalColors.textPrimary,
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _questionTextValidator(_QuestionInputControllers question) {
    if (question.hasSubparts) {
      final hasAnySubpartText = question.subparts.any(
        (subpart) => subpart.textController.text.trim().isNotEmpty,
      );
      final bannedOpening = _bannedOpeningError(question.textController.text);
      if (bannedOpening != null) {
        return bannedOpening;
      }
      if (hasAnySubpartText && question.textController.text.trim().isEmpty) {
        return null;
      }
    }

    final requiredError = _requiredValidator(question.textController.text);
    if (requiredError != null) {
      return requiredError;
    }
    return _bannedOpeningError(question.textController.text);
  }

  String? _subpartValidator(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) {
      return requiredError;
    }
    return _bannedOpeningError(value);
  }

  String? _bannedOpeningError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    const bannedWords = {
      'what',
      'where',
      'why',
      'when',
      'how',
      'brief',
      'explain',
      'compare',
    };

    final normalized = text.toLowerCase();
    final match = RegExp(r'^[a-z]+').firstMatch(normalized);
    final firstWord = match?.group(0);

    if (firstWord != null && bannedWords.contains(firstWord)) {
      return 'Rewrite your question. Do not start with "$firstWord".';
    }

    return null;
  }

  String _subpartLabel(int index) {
    if (index < 26) {
      return String.fromCharCode(97 + index);
    }
    return '${index + 1}';
  }

  String _subpartPlacementLabel(SubpartPlacement placement) {
    return switch (placement) {
      SubpartPlacement.indent => '1 tab ahead',
      SubpartPlacement.middle => 'Middle',
    };
  }

  String _imagePlacementLabel(QuestionImagePlacement placement) {
    return switch (placement) {
      QuestionImagePlacement.left => 'Left',
      QuestionImagePlacement.center => 'Middle',
      QuestionImagePlacement.right => 'Right',
    };
  }
}

class _QuestionInputControllers {
  _QuestionInputControllers({
    required this.numberController,
    required this.textController,
    required this.marksController,
    required this.cloController,
    required this.ploController,
    required this.timeController,
  });

  factory _QuestionInputControllers.seeded(int questionNumber) {
    return _QuestionInputControllers(
      numberController: TextEditingController(text: '$questionNumber'),
      textController: TextEditingController(),
      marksController: TextEditingController(),
      cloController: TextEditingController(),
      ploController: TextEditingController(),
      timeController: TextEditingController(text: '5'),
    );
  }

  final TextEditingController numberController;
  final TextEditingController textController;
  final TextEditingController marksController;
  final TextEditingController cloController;
  final TextEditingController ploController;
  final TextEditingController timeController;
  final List<_SubpartInputControllers> subparts = [];
  final List<TextEditingController> optionControllers = [];
  bool hasSubparts = false;
  Uint8List? imageBytes;
  String? imageName;
  QuestionImagePlacement imagePlacement = QuestionImagePlacement.center;
  SubpartPlacement subpartPlacement = SubpartPlacement.indent;

  int get timeMinutesValue =>
      int.tryParse(timeController.text.trim()) ?? 0;

  List<String> get nonEmptyOptions => optionControllers
      .map((controller) => controller.text.trim())
      .where((option) => option.isNotEmpty)
      .toList();

  PaperQuestionData toData() {
    final activeSubparts = hasSubparts
        ? subparts
              .map(
                (subpart) => PaperSubpartData(
                  text: subpart.textController.text.trim(),
                  marks: subpart.marksController.text.trim(),
                ),
              )
              .where((subpart) => subpart.text.isNotEmpty)
              .toList()
        : <PaperSubpartData>[];

    return PaperQuestionData(
      number: numberController.text.trim(),
      text: textController.text.trim(),
      marks: activeSubparts.isEmpty
          ? marksController.text.trim()
          : '${activeSubparts.fold<int>(0, (sum, subpart) => sum + subpart.marksValue)}',
      clo: cloController.text.trim(),
      plo: ploController.text.trim(),
      subparts: activeSubparts,
      options: nonEmptyOptions,
      timeMinutes: timeMinutesValue,
      imageBytes: imageBytes,
      imageName: imageName,
      imagePlacement: imagePlacement,
      subpartPlacement: subpartPlacement,
    );
  }

  AssessmentQuestion toAssessmentQuestion() {
    final paperData = toData();
    final id =
        'Q${numberController.text.trim().isEmpty ? '001' : numberController.text.trim().padLeft(3, '0')}';
    final marksValue = paperData.effectiveMarks;
    final text = paperData.text.isEmpty
        ? paperData.subparts
              .map((subpart) => subpart.text)
              .where((line) => line.isNotEmpty)
              .join('\n')
        : paperData.text;
    final options = paperData.options;

    return AssessmentQuestion(
      id: id,
      type: options.isNotEmpty
          ? QuestionType.mcq
          : QuestionType.shortAnswer,
      question: text.isEmpty ? 'Generated question' : text,
      marks: marksValue == 0 ? 1 : marksValue,
      options: options,
      timeMinutes: paperData.timeMinutes,
    );
  }

  void syncOptionsCount(int count) {
    if (count == optionControllers.length) {
      return;
    }
    if (count > optionControllers.length) {
      for (var index = optionControllers.length; index < count; index++) {
        optionControllers.add(TextEditingController());
      }
      return;
    }
    final removed = optionControllers.sublist(count);
    for (final controller in removed) {
      controller.dispose();
    }
    optionControllers.removeRange(count, optionControllers.length);
  }

  int get subpartMarksTotal {
    return subparts.fold<int>(
      0,
      (sum, subpart) => sum + (int.tryParse(subpart.marksController.text) ?? 0),
    );
  }

  void updateMarksFromSubparts() {
    if (!hasSubparts) {
      return;
    }

    final totalText = '$subpartMarksTotal';
    if (marksController.text == totalText) {
      return;
    }

    marksController.value = marksController.value.copyWith(
      text: totalText,
      selection: TextSelection.collapsed(offset: totalText.length),
      composing: TextRange.empty,
    );
  }

  void syncSubpartCount(int count) {
    if (count == subparts.length) {
      return;
    }

    if (count > subparts.length) {
      for (var index = subparts.length; index < count; index++) {
        subparts.add(_SubpartInputControllers());
      }
      return;
    }

    final removed = subparts.sublist(count);
    for (final subpart in removed) {
      subpart.dispose();
    }
    subparts.removeRange(count, subparts.length);
  }

  void dispose() {
    numberController.dispose();
    textController.dispose();
    marksController.dispose();
    cloController.dispose();
    ploController.dispose();
    timeController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }
    for (final subpart in subparts) {
      subpart.dispose();
    }
  }
}

class _SubpartInputControllers {
  _SubpartInputControllers()
    : textController = TextEditingController(),
      marksController = TextEditingController();

  final TextEditingController textController;
  final TextEditingController marksController;

  void dispose() {
    textController.dispose();
    marksController.dispose();
  }
}
