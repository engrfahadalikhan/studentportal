import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_badge.dart';
import '../models/student.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final student = MockData.studentInfo;
    final showFYP = student.programCode >= 6 && student.programCode <= 8;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Student Info Card
            CustomCard(
              ringColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            const Color(0xFF14b8a6),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Roll No: ${student.rollNo}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Text(
                            'Program: ${student.program}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Text(
                            'Section: ${student.section}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Academic Info Card
            CustomCard(
              ringColor: const Color(0xFF14b8a6).withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.book, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Academic Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Courses Registered
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.05),
                            const Color(0xFF14b8a6).withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Courses Registered',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${MockData.courses.length} courses this semester',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {},
                            child: Row(
                              children: const [
                                Text('View'),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Quick Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.grey.shade200, width: 2),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.map, color: Theme.of(context).primaryColor),
                                const SizedBox(height: 4),
                                const Text('Seating Plan', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.grey.shade200, width: 2),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.calendar_today, color: Theme.of(context).primaryColor),
                                const SizedBox(height: 4),
                                const Text('Date Sheet', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Cases Status
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFecfdf5), Color(0xFFd1fae5)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade100, width: 2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'UFM Cases',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                StatusBadge(
                                  label: MockData.cases['ufm'] == 0 ? 'Clear' : '${MockData.cases['ufm']}',
                                  status: MockData.cases['ufm'] == 0 
                                      ? RequestStatus.approved 
                                      : RequestStatus.rejected,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFecfdf5), Color(0xFFd1fae5)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade100, width: 2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Discipline',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                StatusBadge(
                                  label: MockData.cases['discipline'] == 0 
                                      ? 'Clear' 
                                      : '${MockData.cases['discipline']}',
                                  status: MockData.cases['discipline'] == 0 
                                      ? RequestStatus.approved 
                                      : RequestStatus.rejected,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Requests Card
            CustomCard(
              ringColor: const Color(0xFF9333ea).withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.article, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Requests & Special Sections',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Submit academic requests and applications',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    // Request Types
                    ...MockData.requestTypes.map((request) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.grey.shade50, Colors.grey.shade100],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.file_copy, color: Colors.grey, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      request.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      request.description,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    )),

                    // FYP Section
                    if (showFYP) ...[
                      const Divider(height: 24),
                      const Text(
                        'FINAL YEAR PROJECTS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...MockData.fypRequestTypes.map((request) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {},
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFccfbf1), Color(0xFFa5f3fc)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF14b8a6).withOpacity(0.3), width: 2),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber, color: Color(0xFF14b8a6), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        request.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        request.description,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: Color(0xFF14b8a6)),
                              ],
                            ),
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
